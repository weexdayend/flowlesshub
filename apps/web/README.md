# FlowlessHub Web

Next.js App Router application for the FlowlessHub internal workspace and future client/vendor portal route groups.

## Local development

Run from the repository root after installing the pnpm workspace:

```bash
pnpm --filter @flowlesshub/web dev
```

The app is a foundation shell only. Business workflows are delivered through their approved vertical slices; do not add business logic or financial calculations to the frontend.

Before changing framework-specific APIs, read the installed Next.js version's documentation under `node_modules/next/dist/docs/` and follow `AGENTS.md` in this directory.
