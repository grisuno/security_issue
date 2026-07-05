# Issue #1: portaudio.h missing library 

- **State:** closed
- **Created:** 2023-06-12T00:58:13Z
- **Updated:** 2023-06-12T01:19:34Z
- **Labels:** None

---

  × Building wheel for pyaudio (pyproject.toml) did not run successfully.
  │ exit code: 1
  ╰─> [16 lines of output]
      running bdist_wheel
      running build
      running build_py
      creating build
      creating build/lib.linux-x86_64-cpython-310
      copying src/pyaudio.py -> build/lib.linux-x86_64-cpython-310
      running build_ext
      building '_portaudio' extension
      creating build/temp.linux-x86_64-cpython-310
      creating build/temp.linux-x86_64-cpython-310/src
      gcc -Wno-unused-result -Wsign-compare -DNDEBUG -g -fwrapv -O3 -Wall -fPIC -I/opt/hostedtoolcache/Python/3.10.11/x64/include/python3.10 -c src/_portaudiomodule.c -o build/temp.linux-x86_64-cpython-310/src/_portaudiomodule.o
      src/_portaudiomodule.c:29:10: fatal error: portaudio.h: No such file or directory
         29 | #include "portaudio.h"
            |          ^~~~~~~~~~~~~
      compilation terminated.
      error: command '/usr/bin/gcc' failed with exit code 1
Successfully built numpy matplotlib
      [end of output]
  
  note: This error originates from a subprocess, and is likely not a problem with pip.
  ERROR: Failed building wheel for pyaudio
Failed to build pyaudio
ERROR: Could not build wheels for pyaudio, which is required to install pyproject.toml-based projects
Error: Process completed with exit code 1.

Solution: 

sudo apt install python3-pyaudio
