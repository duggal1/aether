# Security

NativeBrowserEngine Engine 0 is not a hardened production browser sandbox.

The engine parses and executes web-controlled data inside the host process. Do not treat arbitrary hostile pages as safely isolated from the machine, local files, credentials, or agent environment.

Production use against untrusted content requires renderer-process isolation, macOS sandbox entitlements/profiles, strict origin enforcement, CSP/CORS and permission hardening, resource limits, crash containment, parser/runtime fuzzing, dependency and memory-safety review, and dedicated security testing.

Security shortcuts are not performance optimizations. Saving memory by removing isolation is unacceptable once the engine crosses from controlled development fixtures into hostile web execution.
