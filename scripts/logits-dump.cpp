// logits-dump.cpp — exactness-ladder tool for the hybrid campaign.
//
// Two modes:
//   reference: logits-dump -m M -p prompts.jsonl -n N -t tokens.jsonl -g GPU
//              greedy-decode each prompt, record tokens.
//   candidate: logits-dump -m M -p prompts.jsonl --tokens tokens.jsonl -o out.bin -g GPU
//              teacher-force the recorded token sequence; per position dump top-256
//              logits (idx,f32) + tail logsumexp (raw logits, pre-sampler).
//
// Top-k heap fix: earlier versions used std::push_heap/pop_heap with the default
// comparator (a max-heap), so the stored "top-256" was token ids 0-255 plus the
// global argmax. Bins dumped before this fix keep only a valid argmax (top-1);
// KL, top-5 and tail figures computed from them are invalid.
//
// Build (against the PR#27739 tree):
//   clang++ -O2 -std=c++17 logits-dump.cpp -I<llama>/include -I<llama>/ggml/include \
//     -L<llama>/build/bin -lllama -Wl,-rpath,<llama>/build/bin -o logits-dump
#include "llama.h"

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <fstream>
#include <algorithm>
#include <functional>
#include <numeric>
#include <unistd.h>

struct Args {
    std::string model, prompts, tokens, out;
    int n_predict = 128;
    int n_ctx = 8192;
    int n_batch = 512;
    int gpu = 999;   // -1 = CPU only
    int kv = -1;     // -1 = tool default (f16); else GGML_TYPE_*
    bool have_tokens = false;
};

static void die(const char * msg) { fprintf(stderr, "logits-dump: %s\n", msg); fflush(nullptr); _exit(1); }

static std::vector<std::string> load_prompts(const std::string & path) {
    std::vector<std::string> prompts;
    std::ifstream f(path);
    if (!f) die("cannot open prompts file");
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty()) continue;
        // {"prompt": "..."} — extract between the first two quotes after "prompt"
        size_t key = line.find("\"prompt\"");
        if (key == std::string::npos) die("malformed prompt line");
        size_t q1 = line.find('"', key + 9);
        size_t q2 = line.find('"', q1 + 1);
        if (q1 == std::string::npos || q2 == std::string::npos) die("malformed prompt quotes");
        prompts.push_back(line.substr(q1 + 1, q2 - q1 - 1));
    }
    if (prompts.empty()) die("no prompts loaded");
    return prompts;
}

static std::string unescape(const std::string & s) { // minimal: \n \t \\ \"
    std::string out; out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\\' && i + 1 < s.size()) {
            char c = s[i+1];
            if (c == 'n') { out += '\n'; ++i; continue; }
            if (c == 't') { out += '\t'; ++i; continue; }
            if (c == '\\') { out += '\\'; ++i; continue; }
            if (c == '"') { out += '"'; ++i; continue; }
        }
        out += s[i];
    }
    return out;
}

int main(int argc, char ** argv) {
    Args a;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        auto next = [&]() -> const char * { return ++i < argc ? argv[i] : (die("missing value"), ""); };
        if (arg == "-m") a.model = next();
        else if (arg == "-p") a.prompts = next();
        else if (arg == "-n") a.n_predict = atoi(next());
        else if (arg == "--tokens") { a.tokens = next(); a.have_tokens = true; }
        else if (arg == "-t") a.tokens = next();
        else if (arg == "-o") a.out = next();
        else if (arg == "-g") a.gpu = atoi(next());
        else if (arg == "-k") { std::string k = next(); if (k=="f16") a.kv=GGML_TYPE_F16; else if (k=="q8_0") a.kv=GGML_TYPE_Q8_0; else if (k=="q4_0") a.kv=GGML_TYPE_Q4_0; else die("bad -k value"); }
        else if (arg == "-c") a.n_ctx = atoi(next());
        else if (arg == "-b") a.n_batch = atoi(next());
        else die("unknown arg");
    }
    if (a.model.empty() || a.prompts.empty()) die("usage: -m MODEL -p PROMPTS.jsonl [-n N] [-t TOKENS] [-o OUT] [-g GPU]");

    llama_backend_init();
    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = a.gpu;
    mp.use_extra_bufts = false;  // --no-repack: repacking blows a 188GB model into anonymous memory
    // keep the PLE n-gram table host-side: same placement as the serving config's
    // -ot ple_ngram_embd=CPU / -ot per_layer_token_embd=CPU (Metal cannot fit it)
    static ggml_backend_buffer_type_t cpu_buft = ggml_backend_cpu_buffer_type();
    static const llama_model_tensor_buft_override buft_overrides[] = {
        { "per_layer_token_embd", cpu_buft },
        { "ple_ngram_embd",       cpu_buft },
        { nullptr, nullptr },
    };
    mp.tensor_buft_overrides = buft_overrides;
    llama_model * model = llama_model_load_from_file(a.model.c_str(), mp);
    if (!model) die("model load failed");

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = a.n_ctx;
    cp.n_batch = a.n_batch;
    if (a.kv >= 0) { cp.type_k = (ggml_type) a.kv; cp.type_v = (ggml_type) a.kv; }
    llama_context * ctx = llama_new_context_with_model(model, cp);
    if (!ctx) die("context failed");

    const struct llama_vocab * vocab = llama_model_get_vocab(model);
    const int n_vocab = llama_vocab_n_tokens(vocab);
    const llama_token eos = llama_vocab_eos(vocab);
    auto prompts = load_prompts(a.prompts);

    // token sequences: either loaded (candidate mode) or produced (reference mode)
    std::vector<std::vector<llama_token>> all_tokens(prompts.size());

    FILE * out_fp = nullptr;
    if (a.have_tokens) {
        if (a.out.empty()) die("candidate mode needs -o");
        std::ifstream tf(a.tokens);
        if (!tf) die("cannot open tokens file");
        size_t line_no = 0;
        std::string line;
        while (std::getline(tf, line)) {
            if (line.empty()) continue;
            if (line_no >= prompts.size()) die("tokens file has more prompts");
            std::vector<llama_token> toks;
            char * s = &line[0];
            for (char * q = strtok(s, " "); q; q = strtok(nullptr, " ")) toks.push_back(atoi(q));
            all_tokens[line_no++] = std::move(toks);
        }
        if (line_no < prompts.size()) die("tokens file has fewer prompts");
        out_fp = fopen(a.out.c_str(), "wb");
        if (!out_fp) die("cannot open output");
    }

    FILE * tok_fp = nullptr;
    if (!a.have_tokens) {
        if (a.tokens.empty()) die("reference mode needs -t TOKENS.jsonl");
        tok_fp = fopen(a.tokens.c_str(), "w");
        if (!tok_fp) die("cannot open tokens output");
    }

    const int TOPK = 256;
    std::vector<float> logits(n_vocab);
    std::vector<std::pair<float, int>> top(TOPK);

    for (size_t pi = 0; pi < prompts.size(); ++pi) {
        std::string text = unescape(prompts[pi]);
        std::vector<llama_token> in_tok(2048);
        int32_t n_in = llama_tokenize(vocab, text.c_str(), (int32_t) text.size(), in_tok.data(), (int32_t) in_tok.size(), true, true);
        if (n_in < 0) die("tokenize failed");
        in_tok.resize(n_in);
        std::vector<llama_token> seq = in_tok;
        std::vector<llama_token> forced = a.have_tokens ? all_tokens[pi] : std::vector<llama_token>();

        auto decode = [&](int n_used) -> const float * {
            llama_batch b = llama_batch_init(1, 0, 1);
            b.n_tokens = 1;
            b.token[0] = seq[n_used - 1];
            b.pos[0] = n_used - 1;
            b.n_seq_id[0] = 1; b.seq_id[0][0] = 0;
            b.logits[0] = true;
            if (llama_decode(ctx, b) != 0) die("decode failed");
            llama_batch_free(b);
            return llama_get_logits(ctx);
        };

        // feed prompt (batched; logits only on the final prompt token, required by M-RoPE:
        // positions must strictly increase, so the last token must not be decoded twice)
        for (size_t i = 0; i < in_tok.size(); i += a.n_batch) {
            size_t n = std::min<size_t>(a.n_batch, in_tok.size() - i);
            llama_batch b = llama_batch_init(n, 0, 1);
            b.n_tokens = n;
            for (size_t j = 0; j < n; ++j) {
                b.token[j] = in_tok[i+j]; b.pos[j] = i+j; b.n_seq_id[j] = 1; b.seq_id[j][0] = 0;
                b.logits[j] = (i + j == in_tok.size() - 1);
            }
            if (llama_decode(ctx, b) != 0) die("prompt decode failed");
            llama_batch_free(b);
        }

        size_t n_positions = a.have_tokens ? forced.size() : (size_t) a.n_predict;

        std::vector<llama_token> gen;
        for (size_t k = 0; k < n_positions; ++k) {
            if (a.have_tokens) {
                // candidate mode: dump logits at current position (context = prompt + forced[:k]);
                // k==0 uses the logits already produced by the prompt batch
                size_t n_ctx_used = in_tok.size() + k;
                if (k > 0) {
                    decode((int) n_ctx_used);
                }
                const float * lg = llama_get_logits(ctx);
                // top-256 + tail lse
                top.clear();
                for (int v = 0; v < n_vocab; ++v) {
                    if ((int) top.size() < TOPK) {
                        top.emplace_back(lg[v], v);
                        std::push_heap(top.begin(), top.end(), std::greater<>());
                    } else if (lg[v] > top.front().first) {
                        std::pop_heap(top.begin(), top.end(), std::greater<>());
                        top.back() = {lg[v], v};
                        std::push_heap(top.begin(), top.end(), std::greater<>());
                    }
                }
                float mx = top.empty() ? 0.f : std::max_element(top.begin(), top.end())->first;
                float lse = mx;
                { double s = 0; for (int v = 0; v < n_vocab; ++v) s += expf(lg[v] - mx); lse += (float) log(s); }
                fwrite(&pi, sizeof(uint32_t), 1, out_fp);
                fwrite(&k, sizeof(uint32_t), 1, out_fp);
                fwrite(&lse, sizeof(float), 1, out_fp);
                uint32_t kk = (uint32_t) top.size();
                fwrite(&kk, sizeof(uint32_t), 1, out_fp);
                std::sort(top.begin(), top.end(), [](auto & x, auto & y){ return x.first > y.first; });
                for (auto & [val, idx] : top) { int32_t iv = idx; fwrite(&iv, sizeof(int32_t), 1, out_fp); fwrite(&val, sizeof(float), 1, out_fp); }
                // append the FORCED token (from reference run)
                seq.push_back(forced[k]);
            } else {
                // reference mode: greedy decode, record token; k==0 uses prompt-batch logits
                size_t n_ctx_used = in_tok.size() + k;
                if (k > 0) {
                    decode((int) n_ctx_used);
                }
                const float * lg = llama_get_logits(ctx);
                llama_token t = 0; float best = -1e30f;
                for (int v = 0; v < n_vocab; ++v) if (lg[v] > best) { best = lg[v]; t = v; }
                if (t == eos) break;
                gen.push_back(t);
                seq.push_back(t);
            }
        }

        if (!a.have_tokens) {
            for (size_t i = 0; i < gen.size(); ++i) fprintf(tok_fp, "%s%d", i ? " " : "", gen[i]);
            fprintf(tok_fp, "\n");
        }
        // reset context between prompts
        llama_memory_clear(llama_get_memory(ctx), false);
        fflush(out_fp ? out_fp : tok_fp);
        fprintf(stderr, "prompt %zu/%zu done\n", pi + 1, prompts.size());
    }

    if (out_fp) { fclose(out_fp); }
    if (tok_fp) { fclose(tok_fp); }
    // NOTE: skip llama_free/model_free/backend_free on purpose: this fork's Metal backend
    // aborts in ggml_metal_device_free (residency-sets assert) at teardown. For a one-shot
    // measurement tool the OS reclaims everything; flushing files first is the correctness
    // requirement.
    _exit(0);
}
