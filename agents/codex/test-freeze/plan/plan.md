# Test freeze investigation

Establish host baseline, trace the test/build and render paths, and reproduce under an external process-tree RSS/time watchdog. Preserve existing files (this directory is untracked in a parent home-directory Git repository).

Success: identify demonstrated causes, fix confirmed defects, provide a serial bounded test entry point with measured process CPU/RSS and system GPU/swap observations, and run applicable regression tests. Historical freeze peaks cannot be reconstructed without telemetry.

Initial evidence: 8 GiB / 8 CPUs; no engine test process; five opencode processes together consume approximately 450-490% CPU, swap used 6746.62 MiB, compressor occupies 3.14 GiB. Do not terminate unrelated user agents. Inspect tests before execution; build with one job and run tests serially.
