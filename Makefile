## it is important to have a proper sha1 value of the previsous
## release, i.e. the online version.
PREVIOUS_RELEASE=23c28e3b44ab4f9d2a97838f9698797337b8f3ed
#PREVIOUS_RELEASE=$(shell git rev-parse HEAD)


PREFIX:=../
DEST:=$(PREFIX)$(PROJECT)
REBAR=deps/rebar/rebar

THIS_RELEASE_SHA1=$(shell git rev-parse HEAD)


.PHONY: all edoc test clean build_plt dialyzer app

all: deps src/fingerprint.erl appups
	$(REBAR) compile

deps: deps/.got

deps/.got: $(REBAR)
	rm -rf deps/.got
	$(REBAR) get-deps && :> deps/.got

src/fingerprint.erl:
	bash generate_fingerprint.sh

.PHONY: appups
appups:
	cd appups; bash -x install_appups.sh

edoc: all
	@$(REBAR) doc

test: ct
	@rm -rf .eunit
	@mkdir -p .eunit
	@$(REBAR) eunit

clean:
	@rm src/fingerprint.erl; $(REBAR) clean; rm -fr deps

app:
	@[ -z "$(PROJECT)" ] && echo "ERROR: required variable PROJECT missing" 1>&2 && exit 1 || true
	@$(REBAR) -r create template=mochiwebapp dest=$(DEST) appid=$(PROJECT)

.PHONY: me
me:
	(cd appups; bash install_appups.sh); $(REBAR) -r compile skip_deps=true
.PHONY: ct
ct:
	$(REBAR) clean; EUNIT_TEST=true $(REBAR) -r compile; $(REBAR) -r skip_deps=true ct

.PHONY: rel


rel:
	$(REBAR) generate; bash init_start_boot.sh

relup: previous_release
	$(REBAR) generate; bash init_start_boot.sh; cd rel; ../$(REBAR) previous_release=../previous_release/$(PREVIOUS_RELEASE)/rel/msync generate-upgrade


# the rebar from wcy123, it has a patch to support dynamic application
# vsn in .appup.src
deps/rebar/rebar:
	mkdir deps; git clone git@github.com:wcy123/rebar deps/rebar; (cd deps/rebar; git checkout master; ./bootstrap)

# in order to generate proper
.PHONY: previous_release
previous_release:
	$(SHELL) -x build_previous_release.sh $(PREVIOUS_RELEASE)

.PHONY: generate_appups
generate_appups:
	cd appups; bash reset_appup.sh; ../generate_appups ../rel/msync ../previous_release/$(PREVIOUS_RELEASE)/rel/msync

.PHONY: install_appups
install_appups:
	(cd appups; bash install_appups.sh)
