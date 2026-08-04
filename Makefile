SOURCES := $(wildcard src/*.c src/*.h)

.PHONY: all universal package clean

all: hitmango

hitmango: build.sh $(SOURCES)
	./build.sh

universal: build_universal.sh $(SOURCES)
	./build_universal.sh

package: universal
	HGO_SKIP_BUILD=1 ./package/build-package.sh

clean:
	$(RM) hitmango hitmango-universal
	$(RM) -r .build
