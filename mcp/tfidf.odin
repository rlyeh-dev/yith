package necronomicon_mcp

import "core:math"

@(private = "package")
Document :: struct {
	id:     int,
	name:   string,
	tokens: []string,
}

@(private = "package")
Vocab :: struct {
	word_to_index: map[string]int,
	doc_frequency: []int, // how many docs contain each word
	total_docs:    int,
}

@(private = "package")
Tfidf :: struct {
	vocab: Vocab,
	docs:  [dynamic]Document,
	idf:   []f32,
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
	tfidf.vocab.total_docs = len(tfidf.docs)

	for doc in tfidf.docs {
		seen := make(map[string]bool)
		defer delete(seen)
		for token in doc.tokens {
			if token not_in seen {
				idx := tfidf.vocab.word_to_index[token]
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
		tfidf.idf[i] = math.ln(total / (df + 1.0))
	}
}

process_doc_vectors :: proc(doc: ^Document) {
	// todo
}

build_api_index :: proc(server: ^Mcp_Server) {
	build_vocabulary(&server.api_index)
	calculate_idf(&server.api_index)
	for doc in server.api_index.docs {
		// maybe i jsut store the vectors and normalized vectors in the doc record?
		// build_doc_vectors(&server.api_index, doc)
		// normalize_doc_vectors(&server.api_index, doc)
	}
}
