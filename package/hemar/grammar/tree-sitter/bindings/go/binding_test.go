package tree_sitter_hemar_test

import (
	"testing"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_hemar "github.com/hectic-lab/util.nix/bindings/go"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_hemar.Language())
	if language == nil {
		t.Errorf("Error loading Hemar grammar")
	}
}
