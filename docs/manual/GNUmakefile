LATEXMK ?= latexmk
TARGETS := manual manual-en

.PHONY: all clean

all: $(addsuffix .pdf,$(TARGETS))

%.pdf: %.tex ../../assets/graphics/intro.png ../../assets/graphics/stepup_logo.png
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error $<

clean:
	$(LATEXMK) -C $(addsuffix .tex,$(TARGETS))
