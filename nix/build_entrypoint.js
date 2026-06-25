// Minimal entrypoint for prefetching Deno deps in the Nix build.
// Includes only the imports used by the `package` task, omitting test-only
// deps (puppeteer, deno-dom, fileServer) from make.js.
import * as fs from "@std/fs";
import * as path from "@std/path";
import { abort, desc, run, task } from "https://deno.land/x/drake@v1.5.1/mod.ts";
import JSON5 from "npm:json5";
