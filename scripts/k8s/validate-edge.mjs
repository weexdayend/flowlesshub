#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";

const ROOT = process.cwd();
const CADDY_IMAGE = "caddy:2.11.9-alpine";
const CADDY_FILES = ["Caddyfile.local", "Caddyfile.production", "routes.caddy"];

function fail(message) {
  const error = new Error(message);
  error.edgeValidationFailure = true;
  throw error;
}

function readRepoFile(relativePath) {
  const absolutePath = path.join(ROOT, relativePath);
  if (!existsSync(absolutePath)) fail(`required file is missing: ${relativePath}`);
  // Keep manifest contract checks portable across Windows CRLF and Linux LF checkouts.
  return readFileSync(absolutePath, "utf8").replace(/\r\n/g, "\n");
}

function requireMatch(source, expression, description) {
  if (!expression.test(source)) fail(`manifest contract not satisfied: ${description}`);
}

function validateDeployment(file, name) {
  const source = readRepoFile(`deploy/k8s/base/${file}`);
  requireMatch(source, new RegExp(`^  name: ${name}$`, "m"), `${file} metadata.name=${name}`);
  requireMatch(
    source,
    new RegExp(`^  selector:\\n    matchLabels:\\n      app\\.kubernetes\\.io/name: ${name}$`, "m"),
    `${file} Deployment selector matches ${name}`,
  );
  requireMatch(
    source,
    new RegExp(`^  template:\\n    metadata:\\n      labels:\\n        app\\.kubernetes\\.io/name: ${name}$`, "m"),
    `${file} Pod template label matches ${name}`,
  );
}

function validateService(file, serviceName, selectorName) {
  const source = readRepoFile(`deploy/k8s/base/${file}`);
  requireMatch(source, new RegExp(`^  name: ${serviceName}$`, "m"), `${file} metadata.name=${serviceName}`);
  requireMatch(source, /^  type: ClusterIP$/m, `${file} remains ClusterIP`);
  requireMatch(
    source,
    new RegExp(`^  selector:\\n    app\\.kubernetes\\.io/name: ${selectorName}$`, "m"),
    `${file} Service selector matches Pod label ${selectorName}`,
  );
}

function validateManifests() {
  validateDeployment("api-deployment.yaml", "flowlesshub-api");
  validateDeployment("api-green-deployment.yaml", "flowlesshub-api-green");
  validateDeployment("web-deployment.yaml", "flowlesshub-web");
  validateDeployment("web-green-deployment.yaml", "flowlesshub-web-green");

  validateService("api-blue-service.yaml", "flowlesshub-api-blue", "flowlesshub-api");
  validateService("api-green-service.yaml", "flowlesshub-api-green", "flowlesshub-api-green");
  validateService("web-blue-service.yaml", "flowlesshub-web-blue", "flowlesshub-web");
  validateService("web-green-service.yaml", "flowlesshub-web-green", "flowlesshub-web-green");

  const edgeDeployment = readRepoFile("deploy/k8s/base/edge-deployment.yaml");
  requireMatch(edgeDeployment, /^          image: caddy:2\.11\.9-alpine$/m, "edge uses pinned Caddy 2.11.9 image");
  requireMatch(edgeDeployment, /^  replicas: 2$/m, "edge has two replicas");
  requireMatch(edgeDeployment, /^      maxUnavailable: 0$/m, "edge rollout preserves at least one available edge Pod");
  requireMatch(edgeDeployment, /FLOWLESSHUB_ACTIVE_COLOR/, "edge receives active color configuration");
  requireMatch(edgeDeployment, /flowlesshub-api-\$\{FLOWLESSHUB_ACTIVE_COLOR\}[^\n]*\/readyz/, "edge readiness probes selected API");
  requireMatch(edgeDeployment, /flowlesshub-web-\$\{FLOWLESSHUB_ACTIVE_COLOR\}[^\n]*\//, "edge readiness probes selected Web");

  const edgeService = readRepoFile("deploy/k8s/base/edge-service.yaml");
  requireMatch(edgeService, /^  name: flowlesshub-edge$/m, "edge Service exists");
  requireMatch(edgeService, /^  type: ClusterIP$/m, "base edge Service is not public");

  const kustomization = readRepoFile("deploy/k8s/base/kustomization.yaml");
  requireMatch(kustomization, /^configMapGenerator:$/m, "Caddy config is generated from source files");
  for (const file of CADDY_FILES) {
    requireMatch(kustomization, new RegExp(` ${file.replaceAll(".", "\\.")}=`), `Kustomize includes ${file}`);
  }

  console.log("edge-validate: blue/green Deployment, Pod, Service, edge and Kustomize source checks passed.");
}

function runDocker(label, args) {
  console.log(`\n==> ${label}`);
  const result = spawnSync("docker", args, {
    cwd: ROOT,
    encoding: "utf8",
    windowsHide: true,
    maxBuffer: 8 * 1024 * 1024,
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) fail(`${label}: ${result.error.message}`);
  if (result.status !== 0) fail(`${label} failed with exit code ${result.status ?? "unknown"}`);
}

function validateCaddy() {
  const sourceDir = path.join(ROOT, "deploy", "k8s", "base", "caddy");
  if (!existsSync(sourceDir)) fail("Caddy source directory is missing.");

  const tempDir = mkdtempSync(path.join(os.tmpdir(), "flowlesshub-caddy-"));
  try {
    for (const file of CADDY_FILES) {
      const source = path.join(sourceDir, file);
      if (!existsSync(source)) fail(`Caddy source file is missing: ${file}`);
      copyFileSync(source, path.join(tempDir, file));
    }

    // Docker Desktop accepts forward-slash absolute Windows paths in --mount.
    const mountSource = tempDir.replaceAll("\\", "/");
    if (mountSource.includes(",")) fail(`temporary path contains a comma and cannot be represented as a Docker mount: ${mountSource}`);
    const mount = `type=bind,source=${mountSource},target=/etc/caddy,readonly`;
    const common = [
      "run", "--rm", "--network", "none",
      "--mount", mount,
      "--env", "FLOWLESSHUB_ACTIVE_COLOR=blue",
      "--env", "FLOWLESSHUB_SITE_ADDRESS=flowlesshub.invalid",
      CADDY_IMAGE,
    ];

    runDocker("Validate local Caddyfile", [
      ...common,
      "caddy", "validate", "--config", "/etc/caddy/Caddyfile.local", "--adapter", "caddyfile",
    ]);

    runDocker("Adapt production Caddyfile", [
      ...common,
      "caddy", "adapt", "--config", "/etc/caddy/Caddyfile.production", "--adapter", "caddyfile", "--pretty",
    ]);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}

try {
  validateManifests();
  runDocker("Pull pinned Caddy validator image", ["pull", CADDY_IMAGE]);
  validateCaddy();
  console.log("\nedge-validate: all checks passed.");
} catch (error) {
  process.exitCode = 1;
  if (error?.edgeValidationFailure) console.error(`edge-validate: ERROR: ${error.message}`);
  else console.error(`edge-validate: ERROR: ${error?.stack ?? error}`);
}
