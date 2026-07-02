/*============================================================================
  epub2txt2  mayhem/fuzz_epub2txt.c

  IN-PROCESS libFuzzer harness for epub2txt2's XML / XHTML parsing surface.

  WHY THIS EXISTS
  ---------------
  The original Mayhem target ran the `epub2txt <file.epub>` CLI. But epub2txt
  does NOT read the input itself: epub2txt_do_file() shells out to the system
  `unzip` binary (run_command{"unzip",...}) to expand the EPUB (a ZIP) into a
  tempdir, and only the *unzip child* touches @@. The monitored target never
  reads the input, so Mayhem reports "the target isn't reading inputs" and the
  campaign makes no progress.

  The genuinely interesting bug surface is NOT the system unzip — it is the
  in-process XML/HTML parsing that epub2txt runs over the *already-unzipped*
  documents:
    - the bundled sxmlc DOM parser (src/sxmlc.c, XMLDoc_parse_buffer_DOM) that
      epub2txt uses for container.xml and the OPF, and
    - the hand-rolled XHTML state machine (src/xhtml.c, xhtml_to_stdout /
      xhtml_file_to_stdout) that renders each spine document to text
      (tags, entities, ruby, UTF-8/UTF-32 char transforms).

  This harness skips the zip/unzip layer entirely and feeds the fuzz bytes
  DIRECTLY to those in-process parsers, in the same way epub2txt feeds them a
  single unzipped document:

    1. XHTML path  : write the bytes to a temp file and call
                     xhtml_file_to_stdout() -- the exact per-spine-file handler
                     epub2txt_do_file() invokes after unzip. It reads the file
                     in-process (wstring_create_from_utf8_file) and runs the
                     full xhtml_to_stdout state machine.

    2. sxmlc path  : pass the same bytes (NUL-terminated) straight to
                     XMLDoc_parse_buffer_DOM() -- the OPF/container.xml DOM
                     parser, the other attacker-controlled in-process surface.

  No fork, no unzip, no child process: the monitored process reads and parses
  the input itself, so coverage feedback works.

  Builds two binaries (see mayhem/build.sh):
    /mayhem/epub2txt-fuzz             libFuzzer (-fsanitize=fuzzer)
    /mayhem/epub2txt-fuzz-standalone  StandaloneFuzzTargetMain.c reproducer
============================================================================*/

#define _GNU_SOURCE 1

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

#include "defs.h"
#include "epub2txt.h"
#include "xhtml.h"
#include "sxmlc.h"

/* Discard stdout text rendering so the fuzzer isn't bottlenecked on terminal
   I/O and the log stays readable. Open /dev/null once, lazily. */
static FILE *sink (void)
  {
  static FILE *devnull = NULL;
  if (!devnull)
    devnull = fopen ("/dev/null", "w");
  return devnull;
  }

/* Drive xhtml_file_to_stdout() exactly as epub2txt_do_file() does after unzip:
   it expects a path to an (already-extracted) XHTML document, reads it
   in-process, and runs the full xhtml_to_stdout state machine. */
static void fuzz_xhtml (const uint8_t *data, size_t size)
  {
  char tmpl[] = "/tmp/e2t_fuzz.XXXXXX";
  int fd = mkstemp (tmpl);
  if (fd < 0)
    return;

  if (size)
    {
    size_t off = 0;
    while (off < size)
      {
      ssize_t w = write (fd, data + off, size - off);
      if (w <= 0)
        break;
      off += (size_t) w;
      }
    }
  close (fd);

  /* Exercise a couple of option combinations through the same parser:
     default rendering, and the raw/ascii/ansi path (different code in
     xhtml_transform_char / xhtml_emit_format). */
  Epub2TxtOptions opts;
  char *error = NULL;

  memset (&opts, 0, sizeof (opts));
  opts.width = 80;
  FILE *saved = stdout;
  FILE *nul = sink ();
  if (nul) stdout = nul;
  xhtml_file_to_stdout (tmpl, &opts, &error);
  stdout = saved;
  if (error) { free (error); error = NULL; }

  memset (&opts, 0, sizeof (opts));
  opts.width = 80;
  opts.ascii = TRUE;
  opts.ansi  = TRUE;
  opts.raw   = FALSE;
  if (nul) stdout = nul;
  xhtml_file_to_stdout (tmpl, &opts, &error);
  stdout = saved;
  if (error) { free (error); error = NULL; }

  unlink (tmpl);
  }

/* Drive the bundled sxmlc DOM parser directly on the buffer -- this is the
   container.xml / OPF parse path (XMLDoc_parse_buffer_DOM) that epub2txt runs
   in-process. Buffer-based API, so no temp file needed; just NUL-terminate. */
static void fuzz_sxmlc (const uint8_t *data, size_t size)
  {
  char *buf = (char *) malloc (size + 1);
  if (!buf)
    return;
  if (size)
    memcpy (buf, data, size);
  buf[size] = '\0';

  XMLDoc doc;
  XMLDoc_init (&doc);
  if (XMLDoc_parse_buffer_DOM (buf, "fuzz", &doc))
    {
    /* Walk the root a little so we touch node/attribute accessors the way
       epub2txt's OPF readers do. */
    XMLNode *root = XMLDoc_root (&doc);
    if (root)
      {
      int i;
      for (i = 0; i < root->n_children; i++)
        {
        XMLNode *c = root->children[i];
        if (c && c->tag)
          (void) strlen (c->tag);
        }
      }
    }
  XMLDoc_free (&doc);
  free (buf);
  }

int LLVMFuzzerTestOneInput (const uint8_t *data, size_t size)
  {
  fuzz_xhtml (data, size);
  fuzz_sxmlc (data, size);
  return 0;
  }
