package forensics

import (
	"math"
)

// CalculateEntropy computes the Shannon entropy of a byte slice.
// Returns a value between 0.0 (no randomness) and 8.0 (completely random).
// Typical text/code is < 5.0. Encrypted/Compressed/Obfuscated code is > 7.0.
func CalculateEntropy(data []byte) float64 {
	if len(data) == 0 {
		return 0
	}

	frequencies := make(map[byte]float64)
	for _, b := range data {
		frequencies[b]++
	}

	dataLen := float64(len(data))
	entropy := 0.0

	for _, count := range frequencies {
		freq := count / dataLen
		entropy -= freq * math.Log2(freq)
	}

	return entropy
}
