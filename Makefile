PROG := pipelined

all: *.v
	iverilog -o $(PROG) $^

doc: pipelined.pdf

pipelined.pdf: pipelined.tex
	pdflatex $<

.PHONY: clean
clean:
	rm -f $(PROG)
