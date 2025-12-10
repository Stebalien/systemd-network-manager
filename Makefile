CARGO_TARGET_DIR ?= target
PREFIX           ?= /usr/local
LIBDIR           ?= $(PREFIX)/lib
LIBEXECDIR       ?= $(LIBDIR)

export CARGO_TARGET_DIR

BIN = $(CARGO_TARGET_DIR)/release/systemd-network-manager

USER_UNIT_SOURCES := $(wildcard units/user/*.in)
SYSTEM_UNIT_SOURCES := $(wildcard units/system/*.in)

USER_UNITS := $(filter-out $(USER_UNIT_SOURCES), $(wildcard units/user/*.*)) $(wildcard units/*.*) $(USER_UNIT_SOURCES:.in=)
SYSTEM_UNITS := $(filter-out $(wildcard units/system/*.in), $(wildcard units/system/*.*)) $(wildcard units/*.*) $(SYSTEM_UNIT_SOURCES:.in=)

build: $(BIN) $(USER_UNITS) $(SYSTEM_UNITS)

$(BIN): .
	cargo build --release

%: %.in
	m4 -DBINDIR="$(BINDIR)" \
		-DLIBEXECDIR="$(LIBEXECDIR)" \
		-DPREFIX="$(PREFIX)" \
		$< > $@

install: build install-units
	install -Dm755 $(CARGO_TARGET_DIR)/release/systemd-network-manager $(DESTDIR)$(LIBEXECDIR)/systemd-network-manager

install-user-units: $(USER_UNITS)
	install -Dm644 -t $(DESTDIR)$(LIBDIR)/systemd/user/ $^

install-system-units: $(SYSTEM_UNITS)
	install -Dm644 -t $(DESTDIR)$(LIBDIR)/systemd/system/ $^

install-units: install-user-units install-system-units

clean:
	rm -fr $(CARGO_TARGET_DIR)
	rm $(UNIT_TARGETS)


.PHONY: build install install-units install-system-units install-user-units clean
