/*
Copyright 2026 The Flux authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package notifier

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	. "github.com/onsi/gomega"
)

func TestNewGiteaPullRequestCommentBasic(t *testing.T) {
	g := NewWithT(t)

	handler := func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/user":
			user := map[string]interface{}{
				"id":       1,
				"login":    "test-user",
				"username": "test-user",
			}
			json.NewEncoder(w).Encode(user)
		case "/api/v1/version":
			fmt.Fprintf(w, `{"version":"1.18.3"}`)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}
	srv := httptest.NewServer(http.HandlerFunc(handler))
	t.Cleanup(srv.Close)

	gc, err := NewGiteaPullRequestComment("0c9c2e41-d2f9-4f9b-9c41-bebc1984d67a",
		WithGiteaAddress(srv.URL+"/foo/bar"),
		WithGiteaToken("foobar"),
	)
	g.Expect(err).ToNot(HaveOccurred())
	g.Expect(gc.Owner).To(Equal("foo"))
	g.Expect(gc.Repo).To(Equal("bar"))
	g.Expect(gc.ProviderUID).To(Equal("0c9c2e41-d2f9-4f9b-9c41-bebc1984d67a"))
	g.Expect(gc.Username).To(Equal("test-user"))
}

func TestNewGiteaPullRequestCommentEmptyToken(t *testing.T) {
	g := NewWithT(t)
	_, err := NewGiteaPullRequestComment("0c9c2e41-d2f9-4f9b-9c41-bebc1984d67a",
		WithGiteaAddress("https://gitea.example.com/foo/bar"),
	)
	g.Expect(err).To(HaveOccurred())
}

func TestNewGiteaPullRequestCommentEmptyProviderUID(t *testing.T) {
	g := NewWithT(t)
	_, err := NewGiteaPullRequestComment("",
		WithGiteaAddress("https://gitea.example.com/foo/bar"),
		WithGiteaToken("foobar"),
	)
	g.Expect(err).To(HaveOccurred())
}

func TestNewGiteaPullRequestCommentInvalidUrl(t *testing.T) {
	g := NewWithT(t)

	handler := func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/user":
			user := map[string]interface{}{
				"id":       1,
				"login":    "test-user",
				"username": "test-user",
			}
			json.NewEncoder(w).Encode(user)
		case "/api/v1/version":
			fmt.Fprintf(w, `{"version":"1.18.3"}`)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}
	srv := httptest.NewServer(http.HandlerFunc(handler))
	t.Cleanup(srv.Close)

	_, err := NewGiteaPullRequestComment("0c9c2e41-d2f9-4f9b-9c41-bebc1984d67a",
		WithGiteaAddress(srv.URL+"/foo/bar/baz"),
		WithGiteaToken("foobar"),
	)
	g.Expect(err).To(HaveOccurred())
	g.Expect(err.Error()).To(ContainSubstring("invalid repository id"))
}
