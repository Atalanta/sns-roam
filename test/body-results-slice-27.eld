;; -*- mode: lisp-data -*-
;; The body-search and body-parse results slice 27 recorded before
;; it put the parsing buffers in org-mode.  Read by
;; `sns-roam-body-search-and-parse-return-what-slice-27-recorded'.
(:searches
 (("tide"
   (:id "slice-27-harbour" :title "Harbour" :file "<roam>/harbour.org"
	:line 6 :point 72 :hit-text "| harbour | tide |")
   (:id "slice-27-moon" :title "Moon" :file "<roam>/moon.org" :line 6
	:point 72 :hit-text "The moon sets the TIDE.")
   (:id "slice-27-moon" :title "Moon" :file "<roam>/moon.org" :line 8
	:point 81 :hit-text "- tide one")
   (:id "slice-27-tides" :title "Tide tables" :file "<roam>/tides.org"
	:line 6 :point 62 :hit-text "Tide tables for the harbour.")
   (:id "slice-27-tides" :title "Tide tables" :file "<roam>/tides.org"
	:line 8 :point 97 :hit-text
	"High tide at noon, low tide at six.")
   (:id "slice-27-tides" :title "Tide tables" :file "<roam>/tides.org"
	:line 8 :point 115 :hit-text
	"High tide at noon, low tide at six.")
   (:id "slice-27-tides" :title "Tide tables" :file "<roam>/tides.org"
	:line 10 :point 138 :hit-text "* Spring tides")
   (:id "slice-27-tides" :title "Tide tables" :file "<roam>/tides.org"
	:line 11 :point 176 :hit-text
	"The moon pulls the sea, and the tide follows."))
  ("moon"
   (:id "slice-27-harbour" :title "Harbour" :file "<roam>/harbour.org"
	:line 11 :point 132 :hit-text "Moon over the harbour.")
   (:id "slice-27-moon" :title "Moon" :file "<roam>/moon.org" :line 6
	:point 58 :hit-text "The moon sets the TIDE.")
   (:id "slice-27-moon" :title "Moon" :file "<roam>/moon.org" :line 9
	:point 92 :hit-text "- moon two")
   (:id "slice-27-tides" :title "Tide tables" :file "<roam>/tides.org"
	:line 11 :point 148 :hit-text
	"The moon pulls the sea, and the tide follows."))
  ("harbour"
   (:id "slice-27-harbour" :title "Harbour" :file "<roam>/harbour.org"
	:line 6 :point 62 :hit-text "| harbour | tide |")
   (:id "slice-27-harbour" :title "Harbour" :file "<roam>/harbour.org"
	:line 11 :point 146 :hit-text "Moon over the harbour.")
   (:id "slice-27-tides" :title "Tide tables" :file "<roam>/tides.org"
	:line 6 :point 82 :hit-text "Tide tables for the harbour.")))
 :bodies
 (("Tide tables.\n"
   (paragraph (1 14 1 14 1 0) "Tide tables.\n" ("Tide tables.\n")))
  ("First paragraph.\n\n- one\n- two\n\n| a | b |\n|---+---|\n| 1 | 2 |\n"
   (paragraph (1 19 1 18 1 1) "First paragraph.\n\n"
	      ("First paragraph.\n"))
   (plain-list (19 32 19 31 19 1) "- one\n- two\n\n"
	       ((item (19 25 21 25 19 0) "- one\n"
		      ((paragraph (21 25 21 25 21 0) "one\n" ("one\n"))))
		(item (25 31 27 31 25 0) "- two\n"
		      ((paragraph (27 31 27 31 27 0) "two\n" ("two\n"))))))
   (table (32 62 32 62 32 0) "| a | b |\n|---+---|\n| 1 | 2 |\n"
	  ((table-row (32 42 33 41 32 0) "| a | b |\n"
		      ((table-cell (33 37 34 35 nil 0) " a |" ("a"))
		       (table-cell (37 41 38 39 nil 0) " b |" ("b"))))
	   (table-row (42 52 nil nil 42 0) "|-\n" nil)
	   (table-row (52 62 53 61 52 0) "| 1 | 2 |\n"
		      ((table-cell (53 57 54 55 nil 0) " 1 |" ("1"))
		       (table-cell (57 61 58 59 nil 0) " 2 |" ("2")))))))
  ("#+begin_quote\nThe moon.\n#+end_quote\n\nA [[id:x][link]] and *bold*.[fn:1]\n\n[fn:1] A footnote.\n"
   (quote-block (1 38 15 25 1 1)
		"#+begin_quote\nThe moon.\n#+end_quote\n\n"
		((paragraph (15 25 15 25 15 0) "The moon.\n"
			    ("The moon.\n"))))
   (paragraph (38 74 38 73 38 1)
	      "A [[id:x][link]] and *bold*.[fn:1]\n\n"
	      ("A "
	       (link (40 55 48 52 nil 1) "[[id:x][link]] " ("link"))
	       "and " (bold (59 65 60 64 nil 0) "*bold*" ("bold")) "."
	       (footnote-reference (66 72 nil nil nil 0) "[fn:1]" nil)
	       "\n"))
   (footnote-definition (74 93 81 93 74 0) "[fn:1] A footnote.\n"
			((paragraph (81 93 81 93 81 0) "A footnote.\n"
				    ("A footnote.\n")))))))
