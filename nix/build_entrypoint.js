// Entrypoint for prefetching Deno deps in the Nix build.
//
// `deno run --frozen` resolves every module reachable from make.js -- including
// its `await import(...)` calls, which must therefore be present in the cache
// before the sandboxed build runs. Import them all here so `deno cache --frozen`
// pre-fetches the complete graph.
import * as fs from "@std/fs";
import * as path from "@std/path";
import { abort, desc, run, task } from "https://deno.land/x/drake@v1.5.1/mod.ts";
import JSON5 from "npm:json5";
import "@b-fuze/deno-dom";
import "npm:puppeteer";
import "@std/http/file-server";