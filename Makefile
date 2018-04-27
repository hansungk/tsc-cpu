PROG := pipelined

all: *.v
	iverilog -o $(PROG) $^

.PHONY: clean
clean:
	rm -f $(PROG)
