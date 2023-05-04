VERSION := 2.06
ifdef BUILD_FOR_AFL
CC      := afl-clang-fast
else
CC 		:= gcc
endif
CFLAGS  := -Wall -fPIC -fPIE
#LDFLAGS := -pie -s
LDFLAGS := -pie 
DESTDIR :=
PREFIX  := /usr
BINDIR  := /bin
MANDIR  := /share/man
APPNAME := epub2txt

TARGET	:= epub2txt 
SOURCES := $(sort $(shell find src/ -type f -name *.c))
OBJECTS := $(patsubst src/%,build/%,$(SOURCES:.c=.o))
DEPS	:= $(OBJECTS:.o=.deps)

$(TARGET): $(OBJECTS)
	$(CC) -o $(TARGET) $(LDFLAGS) $(OBJECTS) 

build/%.o: src/%.c
	@mkdir -p build/
	$(CC) $(CFLAGS) -g -DVERSION=\"$(VERSION)\" -DAPPNAME=\"$(APPNAME)\" -MD -MF $(@:.o=.deps) -c -o $@ $< 

clean:
	$(RM) -r build/ $(TARGET) 

install:
	install -D -m 755 $(APPNAME) $(DESTDIR)/$(PREFIX)/$(BINDIR)/$(APPNAME)
	install -D -m 644 man1/epub2txt.1 $(DESTDIR)/$(PREFIX)/$(MANDIR)/man1/epub2txt.1

uninstall:
	rm -f $(DESTDIR)/$(PREFIX)/$(BINDIR)/$(APPNAME)
	rm -f $(DESTDIR)/$(PREFIX)/$(MANDIR)/man1/epub2txt.1

-include $(DEPS)

.PHONY: clean install
