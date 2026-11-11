import type { ReactNode } from "react";

const workstreams = [
  {
    number: "01",
    title: "Commercial control",
    description: "Lead, survey, RAB, quotation, approval, contract and payment terms.",
    state: "Foundation planned",
  },
  {
    number: "02",
    title: "Project delivery",
    description: "Project workspace, phases, milestones, tasks, progress and handover.",
    state: "Foundation planned",
  },
  {
    number: "03",
    title: "Financial visibility",
    description: "Termin, invoices, payments, committed cost and project profitability.",
    state: "Foundation planned",
  },
];

const platformFacts = [
  { label: "Architecture", value: "Go modular monolith" },
  { label: "Workspace", value: "Multi-portal foundation" },
  { label: "Operating model", value: "Plan versus actual" },
];

function Mark({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex size-9 items-center justify-center rounded-xl bg-primary text-sm font-bold text-primary-foreground">
      {children}
    </span>
  );
}

export default function Home() {
  return (
    <main className="min-h-screen bg-background text-foreground">
      <div className="mx-auto flex min-h-screen w-full max-w-[1440px]">
        <aside className="hidden w-[248px] shrink-0 flex-col border-r border-border bg-surface px-5 py-6 lg:flex">
          <div className="flex items-center gap-3 px-1">
            <Mark>F</Mark>
            <div>
              <p className="text-sm font-semibold tracking-tight">FlowlessHub</p>
              <p className="text-xs text-muted">Service operations</p>
            </div>
          </div>

          <div className="mt-10">
            <p className="px-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-muted">
              Workspace
            </p>
            <div className="mt-3 flex items-center gap-3 rounded-xl bg-primary/10 px-3 py-2.5 text-sm font-medium text-primary">
              <span className="size-2 rounded-full bg-primary" />
              Overview
            </div>
          </div>

          <div className="mt-8 space-y-5">
            <SidebarGroup title="Commercial" items={["Leads & surveys", "RAB & quotations", "Contracts"]} />
            <SidebarGroup title="Delivery" items={["Projects", "Tasks & timeline", "UAT & handover"]} />
            <SidebarGroup title="Finance" items={["Invoices & payments", "Procurement", "Project profitability"]} />
            <SidebarGroup title="Service operations" items={["Assets & contracts", "Service desk", "People & capacity"]} />
          </div>

          <div className="mt-auto rounded-2xl border border-border bg-surface-muted p-4">
            <p className="text-xs font-semibold">Foundation workspace</p>
            <p className="mt-1 text-xs leading-5 text-muted">
              Core modules will appear as their delivery checkpoints are completed.
            </p>
          </div>
        </aside>

        <section className="min-w-0 flex-1 px-5 py-6 sm:px-8 lg:px-10">
          <header className="flex flex-wrap items-center justify-between gap-4 border-b border-border pb-5">
            <div className="flex items-center gap-3 lg:hidden">
              <Mark>F</Mark>
              <div>
                <p className="text-sm font-semibold">FlowlessHub</p>
                <p className="text-xs text-muted">Service operations</p>
              </div>
            </div>
            <div className="hidden lg:block">
              <p className="text-xs font-medium text-muted">WORKSPACE / OVERVIEW</p>
              <h1 className="mt-1 text-xl font-semibold tracking-tight">Operations overview</h1>
            </div>
            <div className="ml-auto flex items-center gap-3">
              <span className="rounded-full border border-border bg-surface px-3 py-1.5 text-xs font-medium text-muted">
                S0 · Foundation
              </span>
              <div className="flex size-9 items-center justify-center rounded-full border border-border bg-surface text-xs font-semibold">
                FH
              </div>
            </div>
          </header>

          <div className="py-9 sm:py-12">
            <div className="max-w-3xl">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-primary">
                One workspace. Connected operations.
              </p>
              <h2 className="mt-4 text-3xl font-semibold leading-tight tracking-[-0.04em] sm:text-5xl">
                Keep every project,
                <br className="hidden sm:block" />
                commitment and outcome in view.
              </h2>
              <p className="mt-5 max-w-2xl text-sm leading-7 text-muted sm:text-base">
                FlowlessHub connects the commercial, delivery and financial lifecycle of an IT services business — from the first survey and budget to signed handover and ongoing service.
              </p>
            </div>

            <div className="mt-9 grid gap-3 sm:grid-cols-3">
              {platformFacts.map((fact) => (
                <div key={fact.label} className="rounded-2xl border border-border bg-surface p-4">
                  <p className="text-xs text-muted">{fact.label}</p>
                  <p className="mt-2 text-sm font-semibold">{fact.value}</p>
                </div>
              ))}
            </div>

            <div className="mt-12 flex flex-wrap items-end justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.16em] text-muted">
                  Product workstreams
                </p>
                <h3 className="mt-2 text-xl font-semibold tracking-tight">Built around the real service lifecycle</h3>
              </div>
              <p className="text-xs text-muted">Preview · No live business data yet</p>
            </div>

            <div className="mt-5 grid gap-4 xl:grid-cols-3">
              {workstreams.map((workstream) => (
                <article key={workstream.number} className="rounded-2xl border border-border bg-surface p-5 sm:p-6">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold tracking-[0.14em] text-primary">{workstream.number}</span>
                    <span className="rounded-full bg-surface-muted px-2.5 py-1 text-[10px] font-medium text-muted">
                      {workstream.state}
                    </span>
                  </div>
                  <h4 className="mt-7 text-lg font-semibold tracking-tight">{workstream.title}</h4>
                  <p className="mt-2 min-h-16 text-sm leading-6 text-muted">{workstream.description}</p>
                </article>
              ))}
            </div>

            <footer className="mt-12 flex flex-wrap items-center justify-between gap-3 border-t border-border pt-5 text-xs text-muted">
              <span>FlowlessHub · Product foundation</span>
              <span>Domain-first · Tenant-aware · Auditable</span>
            </footer>
          </div>
        </section>
      </div>
    </main>
  );
}

function SidebarGroup({ title, items }: { title: string; items: string[] }) {
  return (
    <div>
      <p className="px-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-muted">
        {title}
      </p>
      <ul className="mt-2 space-y-1">
        {items.map((item) => (
          <li key={item} className="rounded-lg px-2 py-2 text-xs text-muted">
            {item}
          </li>
        ))}
      </ul>
    </div>
  );
}
