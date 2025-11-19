package miskatonic_mcp

import "core:fmt"
import "core:math"
import "core:mem"
import "core:slice"
import "core:strings"

@(private = "package")
Document :: struct {
	id:     int,
	name:   string,
	tokens: []string,
	vec:    []f32,
}
@(private = "package")
destroy_document :: proc(doc: ^Document) {
	delete(doc.name)
	for tok in doc.tokens {
		delete(tok)
	}
	delete(doc.tokens)
	delete(doc.vec)
}


@(private = "package")
Vocab :: struct {
	word_to_index: map[string]int,
	words:         []string,
	doc_frequency: []int, // how many docs contain each word
	total_docs:    int,
}
@(private = "package")
destroy_vocab :: proc(voc: ^Vocab) {
	delete(voc.word_to_index)
	delete(voc.words)
	delete(voc.doc_frequency)
}

@(private = "package")
Tfidf :: struct {
	// arena:     mem.Arena,
	// arena_mem: []u8,
	vocab: Vocab,
	docs:  [dynamic]Document,
	idf:   []f32,
}

@(private = "package")
destroy_tfidf :: proc(tfidf: ^Tfidf) {
	for &doc in tfidf.docs {
		destroy_document(&doc)
	}
	delete(tfidf.docs)
	destroy_vocab(&tfidf.vocab)
	delete(tfidf.idf)
}

@(private = "package")
build_vocabulary :: proc(tfidf: ^Tfidf) {
	tfidf.vocab.word_to_index = make(map[string]int)
	word_index := 0

	for doc in tfidf.docs {
		for token in doc.tokens {
			if token not_in tfidf.vocab.word_to_index {
				tfidf.vocab.word_to_index[token] = word_index
				word_index += 1
			}
		}
	}

	tfidf.vocab.doc_frequency = make([]int, len(tfidf.vocab.word_to_index))
	tfidf.vocab.words = make([]string, len(tfidf.vocab.word_to_index))
	tfidf.vocab.total_docs = len(tfidf.docs)

	for doc in tfidf.docs {
		seen := make(map[string]bool)
		defer delete(seen)
		for token in doc.tokens {
			if token not_in seen {
				idx := tfidf.vocab.word_to_index[token]
				tfidf.vocab.words[idx] = token
				tfidf.vocab.doc_frequency[idx] += 1
				seen[token] = true
			}
		}
	}
}

@(private = "package")
calculate_idf :: proc(tfidf: ^Tfidf) {
	tfidf.idf = make([]f32, len(tfidf.vocab.word_to_index))

	for i in 0 ..< len(tfidf.idf) {
		df := f32(tfidf.vocab.doc_frequency[i])
		total := f32(tfidf.vocab.total_docs)
		tfidf.idf[i] = math.ln((total + 1.0) / (df + 1.0))
	}
}

@(private = "package")
build_doc_vectors :: proc(tfidf: ^Tfidf, doc: ^Document) {
	doc.vec = make([]f32, len(tfidf.vocab.word_to_index))
	tf := make(map[int]int)
	defer delete(tf)

	for token in doc.tokens {
		idx := tfidf.vocab.word_to_index[token]
		tf[idx] += 1
	}

	doclen := f32(len(doc.tokens))
	for idx, ct in tf {
		doc.vec[idx] = (f32(ct) / doclen) * tfidf.idf[idx]
	}
	sum_sq: f32 = 0
	for val in doc.vec {
		sum_sq += val * val
	}
	normalized := math.sqrt(sum_sq)
	if normalized > 0 {
		for &val in doc.vec {
			val /= normalized
		}
	}
}

@(private = "package")
query_vectors :: proc(tfidf: ^Tfidf, query: string) -> (vec: []f32) {
	tokens := make([dynamic]string)
	defer {
		for tok in tokens {delete(tok)}
		delete(tokens)
	}

	tokenize_prose(&tokens, query)

	vec = make([]f32, len(tfidf.vocab.word_to_index))
	tf := make(map[int]int)
	defer delete(tf)

	for token in tokens {
		if idx, ok := tfidf.vocab.word_to_index[token]; ok {
			tf[idx] += 1
		}
	}
	qlen := f32(len(tokens))
	for idx, ct in tf {
		vec[idx] = (f32(ct) / qlen) * tfidf.idf[idx]
	}
	sum_sq: f32 = 0
	for val in vec {
		sum_sq += val * val
	}
	normalized := math.sqrt(sum_sq)
	if normalized > 0 {
		for &val in vec {
			val /= normalized
		}
	}
	return
}

@(private = "package")
dot_product :: proc(a, b: []f32) -> (dot: f32) {
	for i in 0 ..< len(a) {
		dot += a[i] * b[i]
	}
	return
}

@(private = "package")
add_api_to_index :: proc(tfidf: ^Tfidf, name, description, docs: string) {
	tokens := make([dynamic]string)
	defer delete(tokens)
	tokenize_luadoc(&tokens, documentation = docs, description = description)
	id := len(tfidf.docs) + 1
	doc := Document {
		id     = id,
		name   = strings.clone(name),
		tokens = slice.clone(tokens[:]),
	}
	append(&tfidf.docs, doc)
}

@(private = "package")
build_api_index :: proc(server: ^Server) {
	build_vocabulary(&server.api_index)
	calculate_idf(&server.api_index)
	for &doc in server.api_index.docs {
		build_doc_vectors(&server.api_index, &doc)
	}
}

@(private = "package")
Api_Search_Result :: struct {
	score: f32,
	name:  string,
	index: int,
}
@(private = "package")
destroy_api_search_results :: proc(res: ^[]Api_Search_Result) {
	for r in res {
		delete(r.name)
	}
	delete(res^)
}

@(private = "package")
api_search :: proc(
	server: ^Server,
	query: string,
	result_count := 3,
) -> (
	results: []Api_Search_Result,
) {
	ndocs := len(server.api_index.docs)
	vec := query_vectors(&server.api_index, query)
	defer delete(vec)
	scores := make([]Api_Search_Result, ndocs)
	defer delete(scores)

	for doc, i in server.api_index.docs {
		score := dot_product(vec, doc.vec)
		scores[i] = {
			score = score,
			name  = doc.name,
			index = i,
		}
	}

	nres := len(scores)
	ct := result_count > nres ? nres : result_count
	slice.sort_by(scores, proc(i, j: Api_Search_Result) -> bool {
		return i.score > j.score
	})
	results = slice.clone(scores[:ct])
	for &res in results {
		res.name = strings.clone(res.name)
	}

	return
}
