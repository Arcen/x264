# Makefile

include config.mak

all: default

SRCS = common/mc.c common/predict.c common/pixel.c common/macroblock.c \
       common/frame.c common/dct.c common/cpu.c common/cabac.c \
       common/common.c common/mdate.c common/set.c \
       common/quant.c \
       encoder/analyse.c encoder/me.c encoder/ratecontrol.c \
       encoder/set.c encoder/macroblock.c encoder/cabac.c \
       encoder/cavlc.c encoder/encoder.c encoder/eval.c

SRCCLI = x264.c matroska.c muxers.c

# Visualization sources
ifeq ($(VIS),yes)
SRCS   += common/visualize.c common/display-x11.c
endif

# MMX/SSE optims
ifneq ($(AS),)
X86SRC0 = dct-a.asm deblock-a.asm mc-a.asm mc-a2.asm \
          pixel-a.asm predict-a.asm quant-a.asm sad-a.asm \
          cpu-32.asm dct-32.asm
X86SRC = $(X86SRC0:%=common/x86/%)

ifeq ($(ARCH),X86)
SRCS   += common/x86/mc-c.c common/x86/predict-c.c
ASMSRC  = $(X86SRC) common/x86/pixel-32.asm
OBJASM  = $(ASMSRC:%.asm=%.o)
ASFLAGS += -Icommon/x86/
$(OBJASM): common/x86/x86inc.asm common/x86/x86inc-32.asm
checkasm: tools/checkasm-32.o
endif

ifeq ($(ARCH),X86_64)
SRCS   += common/x86/mc-c.c common/x86/predict-c.c
ASMSRC  = $(X86SRC:-32.asm=-64.asm)
OBJASM  = $(ASMSRC:%.asm=%.o)
ASFLAGS += -Icommon/x86/ -DARCH_X86_64
$(OBJASM): common/x86/x86inc.asm common/x86/x86inc-64.asm
endif
endif

# AltiVec optims
ifeq ($(ARCH),PPC)
ALTIVECSRC += common/ppc/mc.c common/ppc/pixel.c common/ppc/dct.c \
              common/ppc/quant.c common/ppc/deblock.c \
              common/ppc/predict.c
SRCS += $(ALTIVECSRC)
$(ALTIVECSRC:%.c=%.o): CFLAGS += $(ALTIVECFLAGS)
endif

# VIS optims
ifeq ($(ARCH),UltraSparc)
ASMSRC += common/sparc/pixel.asm
OBJASM  = $(ASMSRC:%.asm=%.o)
endif

ifneq ($(HAVE_GETOPT_LONG),1)
SRCS += extras/getopt.c
endif

OBJS = $(SRCS:%.c=%.o)
OBJCLI = $(SRCCLI:%.c=%.o)
DEP  = depend

.PHONY: all default fprofiled clean distclean install install-gtk uninstall dox test testclean

default: $(DEP) x264$(EXE)

libx264.a: .depend $(OBJS) $(OBJASM)
	ar rc libx264.a $(OBJS) $(OBJASM)
	ranlib libx264.a

$(SONAME): .depend $(OBJS) $(OBJASM)
	$(CC) -shared -o $@ $(OBJS) $(OBJASM) -Wl,-soname,$(SONAME) $(LDFLAGS)

x264$(EXE): $(OBJCLI) libx264.a 
	$(CC) -o $@ $+ $(LDFLAGS)

libx264gtk.a: muxers.o libx264.a
	$(MAKE) -C gtk

checkasm: tools/checkasm.o libx264.a
	$(CC) -o $@ $+ $(LDFLAGS)

%.o: %.asm
	$(AS) $(ASFLAGS) -o $@ $<
# delete local/anonymous symbols, so they don't show up in oprofile
	-@ strip -x $@

.depend: config.mak
	rm -f .depend
# Hacky - because gcc 2.9x doesn't have -MT
	$(foreach SRC, $(SRCS) $(SRCCLI), ( $(ECHON) "`dirname $(SRC)`/" && $(CC) $(CFLAGS) $(ALTIVECFLAGS) $(SRC) -MM -g0 ) 1>> .depend;)

config.mak: $(wildcard .svn/entries */.svn/entries */*/.svn/entries)
	./configure $(CONFIGURE_ARGS)

depend: .depend
ifneq ($(wildcard .depend),)
include .depend
endif

SRC2 = $(SRCS) $(SRCCLI)
# These should cover most of the important codepaths
OPT0 = --crf 30 -b1 -m1 -r1 --me dia --no-cabac --pre-scenecut --direct temporal --no-ssim --no-psnr
OPT1 = --crf 16 -b2 -m3 -r3 --me hex -8 --direct spatial --no-dct-decimate
OPT2 = --crf 26 -b2 -m5 -r2 --me hex -8 -w --cqm jvt --nr 100
OPT3 = --crf 18 -b3 -m7 -r5 --me umh -8 -t1 -A all --mixed-refs --b-rdo -w --b-pyramid --direct auto --bime --no-fast-pskip
OPT4 = --crf 22 -b3 -m6 -r4 --me esa -8 -t2 -A all --mixed-refs --b-rdo --bime
OPT5 = --frames 50 --crf 24 -b3 -m7 -r3 --me tesa -8 -t1 --mixed-refs --b-rdo --bime
OPT6 = --frames 50 -q0 -m6 -r2 --me hex -Aall
OPT7 = --frames 50 -q0 -m2 -r1 --me hex --no-cabac

ifeq (,$(VIDS))
fprofiled:
	@echo 'usage: make fprofiled VIDS="infile1 infile2 ..."'
	@echo 'where infiles are anything that x264 understands,'
	@echo 'i.e. YUV with resolution in the filename, y4m, or avisynth.'
else
fprofiled:
	$(MAKE) clean
	mv config.mak config.mak2
	sed -e 's/CFLAGS.*/& -fprofile-generate/; s/LDFLAGS.*/& -fprofile-generate/' config.mak2 > config.mak
	$(MAKE) x264$(EXE)
	$(foreach V, $(VIDS), $(foreach I, 0 1 2 3 4 5 6 7, ./x264$(EXE) $(OPT$I) $(V) --progress -o $(DEVNULL) ;))
	rm -f $(SRC2:%.c=%.o)
	sed -e 's/CFLAGS.*/& -fprofile-use/; s/LDFLAGS.*/& -fprofile-use/' config.mak2 > config.mak
	$(MAKE)
	rm -f $(SRC2:%.c=%.gcda) $(SRC2:%.c=%.gcno)
	mv config.mak2 config.mak
endif

clean:
	rm -f $(OBJS) $(OBJASM) $(OBJCLI) $(SONAME) *.a x264 x264.exe .depend TAGS
	rm -f checkasm checkasm.exe tools/checkasm.o
	rm -f tools/avc2avi tools/avc2avi.exe tools/avc2avi.o
	rm -f $(SRC2:%.c=%.gcda) $(SRC2:%.c=%.gcno)
	- sed -e 's/ *-fprofile-\(generate\|use\)//g' config.mak > config.mak2 && mv config.mak2 config.mak
	$(MAKE) -C gtk clean

distclean: clean
	rm -f config.mak config.h x264.pc
	rm -rf test/
	$(MAKE) -C gtk distclean

install: x264 $(SONAME)
	install -d $(DESTDIR)$(bindir) $(DESTDIR)$(includedir)
	install -d $(DESTDIR)$(libdir) $(DESTDIR)$(libdir)/pkgconfig
	install -m 644 x264.h $(DESTDIR)$(includedir)
	install -m 644 libx264.a $(DESTDIR)$(libdir)
	install -m 644 x264.pc $(DESTDIR)$(libdir)/pkgconfig
	install x264 $(DESTDIR)$(bindir)
	ranlib $(DESTDIR)$(libdir)/libx264.a
	$(if $(SONAME), ln -sf $(SONAME) $(DESTDIR)$(libdir)/libx264.so)
	$(if $(SONAME), install -m 755 $(SONAME) $(DESTDIR)$(libdir))

install-gtk: libx264gtk.a
	$(MAKE) -C gtk install

uninstall:
	rm -f $(DESTDIR)$(includedir)/x264.h $(DESTDIR)$(libdir)/libx264.a
	rm -f $(DESTDIR)$(bindir)/x264 $(DESTDIR)$(libdir)/pkgconfig/x264.pc
	$(if $(SONAME), rm -f $(DESTDIR)$(libdir)/$(SONAME) $(DESTDIR)$(libdir)/libx264.so)
	$(MAKE) -C gtk uninstall

etags: TAGS

TAGS:
	etags $(SRCS)

dox:
	doxygen Doxyfile

ifeq (,$(VIDS))
test:
	@echo 'usage: make test VIDS="infile1 infile2 ..."'
	@echo 'where infiles are anything that x264 understands,'
	@echo 'i.e. YUV with resolution in the filename, y4m, or avisynth.'
else
test:
	perl tools/regression-test.pl --version=head,current --options='$(OPT0)' --options='$(OPT1)' --options='$(OPT2)' $(VIDS:%=--input=%)
endif

testclean:
	rm -f test/*.log test/*.264
	$(foreach DIR, $(wildcard test/x264-r*/), cd $(DIR) ; make clean ; cd ../.. ;)
