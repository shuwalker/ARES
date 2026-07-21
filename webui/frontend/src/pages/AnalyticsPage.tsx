import {
  BarChart3,
  Cpu,
  RefreshCw,
  TrendingUp,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import {
  EMPTY_USAGE_INSIGHTS,
  type UsageBreakdownRow,
  type UsageDailyPoint,
  type UsageInsights,
} from "@/shared/contracts";

const PERIODS = [
  { label: "7d", days: 7 },
  { label: "30d", days: 30 },
  { label: "90d", days: 90 },
] as const;

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

function formatDate(day: string): string {
  try {
    const d = new Date(day + "T00:00:00");
    if (Number.isNaN(d.getTime())) return day;
    return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  } catch {
    return day;
  }
}

function useTableSort<T>(
  data: T[],
  defaultKey: keyof T & string,
  defaultDir: "asc" | "desc" = "desc",
) {
  const [sortKey, setSortKey] = useState<string>(defaultKey);
  const [sortDir, setSortDir] = useState<"asc" | "desc">(defaultDir);

  const sorted = useMemo(() => {
    return [...data].sort((a, b) => {
      const aVal = a[sortKey as keyof T];
      const bVal = b[sortKey as keyof T];
      if (aVal === null || aVal === undefined) return 1;
      if (bVal === null || bVal === undefined) return -1;
      if (aVal === bVal) return 0;
      const cmp = aVal > bVal ? 1 : -1;
      return sortDir === "asc" ? cmp : -cmp;
    });
  }, [data, sortKey, sortDir]);

  const toggle = useCallback(
    (key: string) => {
      if (key === sortKey) {
        setSortDir((d) => (d === "asc" ? "desc" : "asc"));
      } else {
        setSortKey(key);
        setSortDir("desc");
      }
    },
    [sortKey],
  );

  return { sorted, sortKey, sortDir, toggle };
}

function SortHeader({
  label,
  col,
  sortKey,
  sortDir,
  toggle,
  className,
}: {
  label: string;
  col: string;
  sortKey: string;
  sortDir: "asc" | "desc";
  toggle: (key: string) => void;
  className?: string;
}) {
  const active = col === sortKey;
  return (
    <th
      onClick={() => toggle(col)}
      className={`cursor-pointer select-none ${className ?? ""}`}
    >
      <span className="inline-flex items-center gap-1.5 rounded px-1 -mx-1 py-0.5 hover:bg-muted/40 transition-colors">
        {label}
        {active ? (
          sortDir === "asc" ? (
            <span className="text-foreground/80 shrink-0">↑</span>
          ) : (
            <span className="text-foreground/80 shrink-0">↓</span>
          )
        ) : (
          <span className="text-muted shrink-0">↕</span>
        )}
      </span>
    </th>
  );
}

function TokensTooltip({ active, payload, label }: { active?: boolean; payload?: any[]; label?: string }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-md border bg-popover px-3 py-2 text-xs shadow-md">
      <p className="mb-1 font-medium text-popover-foreground">{label}</p>
      {payload.map((entry) => (
        <p key={entry.dataKey} className="flex items-center gap-2 text-popover-foreground">
          <span aria-hidden="true" className="inline-block h-0.5 w-3" style={{ backgroundColor: entry.color }} />
          <span className="font-medium tabular-nums">{formatTokens(Number(entry.value))}</span>
          <span className="text-muted-foreground">{entry.dataKey === "inputTokens" ? "input" : "output"}</span>
        </p>
      ))}
    </div>
  );
}

function TokenBarChart({ daily }: { daily: UsageDailyPoint[] }) {
  if (daily.length === 0) return null;

  const chartData = daily.map((d) => ({
    ...d,
    dayLabel: formatDate(d.date),
  }));

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-2">
          <BarChart3 className="h-5 w-5 text-muted-foreground" />
          <CardTitle className="text-base">Daily Token Usage</CardTitle>
        </div>
        <div className="flex items-center gap-4 text-xs text-muted-foreground">
          <div className="flex items-center gap-1.5">
            <div className="h-2.5 w-2.5 bg-primary" />
            Input
          </div>
          <div className="flex items-center gap-1.5">
            <div className="h-2.5 w-2.5 bg-secondary" />
            Output
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={220}>
          <BarChart data={chartData}>
            <CartesianGrid vertical={false} stroke="var(--border)" />
            <XAxis dataKey="dayLabel" tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} axisLine={{ stroke: "var(--border)" }} tickLine={false} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} axisLine={false} tickLine={false} tickFormatter={formatTokens} width={40} />
            <Tooltip
              content={<TokensTooltip />}
              cursor={{ fill: "var(--muted)" }}
            />
            <Bar dataKey="inputTokens" stackId="tokens" fill="var(--primary)" maxBarSize={24} />
            <Bar dataKey="outputTokens" stackId="tokens" fill="var(--secondary)" radius={[4, 4, 0, 0]} maxBarSize={24} />
          </BarChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  );
}

function DailyTable({ daily }: { daily: UsageDailyPoint[] }) {
  const { sorted, sortKey, sortDir, toggle } = useTableSort(daily, "date", "desc");

  if (daily.length === 0) return null;

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-2">
          <TrendingUp className="h-5 w-5 text-muted-foreground" />
          <CardTitle className="text-base">Daily Breakdown</CardTitle>
        </div>
      </CardHeader>
      <CardContent>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border text-muted-foreground text-xs">
                <SortHeader label="Date" col="date" sortKey={sortKey} sortDir={sortDir} toggle={toggle} className="text-left py-2 pr-4 font-medium" />
                <SortHeader label="Sessions" col="sessions" sortKey={sortKey} sortDir={sortDir} toggle={toggle} className="text-right py-2 px-4 font-medium" />
                <SortHeader label="Input Tokens" col="inputTokens" sortKey={sortKey} sortDir={sortDir} toggle={toggle} className="text-right py-2 px-4 font-medium" />
                <SortHeader label="Output Tokens" col="outputTokens" sortKey={sortKey} sortDir={sortDir} toggle={toggle} className="text-right py-2 pl-4 font-medium" />
              </tr>
            </thead>
            <tbody>
              {sorted.map((d) => (
                <tr
                  key={d.date}
                  className="border-b border-border/50 hover:bg-muted/20 transition-colors"
                >
                  <td className="py-2 pr-4 font-medium">{formatDate(d.date)}</td>
                  <td className="text-right py-2 px-4 text-muted-foreground">{d.sessions}</td>
                  <td className="text-right py-2 px-4 text-primary">{formatTokens(d.inputTokens)}</td>
                  <td className="text-right py-2 pl-4 text-secondary">{formatTokens(d.outputTokens)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  );
}

function ModelTable({ models }: { models: UsageBreakdownRow[] }) {
  const { sorted, sortKey, sortDir, toggle } = useTableSort(models, "inputTokens", "desc");

  if (models.length === 0) return null;

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-2">
          <Cpu className="h-5 w-5 text-muted-foreground" />
          <CardTitle className="text-base">Per-Model Breakdown</CardTitle>
        </div>
      </CardHeader>
      <CardContent>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border text-muted-foreground text-xs">
                <SortHeader label="Model" col="key" sortKey={sortKey} sortDir={sortDir} toggle={toggle} className="text-left py-2 pr-4 font-medium" />
                <SortHeader label="Sessions" col="sessions" sortKey={sortKey} sortDir={sortDir} toggle={toggle} className="text-right py-2 px-4 font-medium" />
                <SortHeader label="Tokens" col="inputTokens" sortKey={sortKey} sortDir={sortDir} toggle={toggle} className="text-right py-2 pl-4 font-medium" />
              </tr>
            </thead>
            <tbody>
              {sorted.map((m) => (
                <tr
                  key={m.key}
                  className="border-b border-border/50 hover:bg-muted/20 transition-colors"
                >
                  <td className="py-2 pr-4">
                    <span className="font-mono text-xs">{m.key}</span>
                  </td>
                  <td className="text-right py-2 px-4 text-muted-foreground">{m.sessions}</td>
                  <td className="text-right py-2 pl-4">
                    <span className="text-primary">{formatTokens(m.inputTokens)}</span>
                    {" / "}
                    <span className="text-secondary">{formatTokens(m.outputTokens)}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  );
}

export function AnalyticsPage() {
  const [days, setDays] = useState(30);
  const [data, setData] = useState<UsageInsights>(EMPTY_USAGE_INSIGHTS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    aresApi
      .insights(days)
      .then(setData)
      .catch((err) => setError(readableError(err, "Failed to load analytics")))
      .finally(() => setLoading(false));
  }, [days]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div className="page-stack">
      <PageHeader
        title="Analytics"
        description="Usage statistics, tokens, and model breakdown."
        action={
          <div className="flex flex-wrap items-center gap-1.5">
            {PERIODS.map((p) => (
              <Button
                key={p.label}
                type="button"
                size="sm"
                variant={days === p.days ? "default" : "outline"}
                onClick={() => setDays(p.days)}
              >
                {p.label}
              </Button>
            ))}
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="text-muted-foreground hover:text-foreground"
              onClick={load}
              disabled={loading}
              aria-label="Refresh"
            >
              <RefreshCw className={loading ? "animate-spin" : ""} />
            </Button>
          </div>
        }
      />

      {error && (
        <Card>
          <CardContent className="py-6">
            <p className="text-sm text-destructive text-center">{error}</p>
          </CardContent>
        </Card>
      )}

      {data && (
        <>
          <div className="grid gap-6 lg:grid-cols-2">
            <Card>
              <CardContent className="py-6 flex flex-col gap-4">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-sm text-muted-foreground">Total Tokens</p>
                    <p className="text-2xl font-semibold tracking-tight">{formatTokens(data.totalTokens)}</p>
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">Total Sessions</p>
                    <p className="text-2xl font-semibold tracking-tight">{data.totalSessions}</p>
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">Input</p>
                    <p className="text-xl font-semibold tracking-tight text-primary">{formatTokens(data.totalInputTokens)}</p>
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">Output</p>
                    <p className="text-xl font-semibold tracking-tight text-secondary">{formatTokens(data.totalOutputTokens)}</p>
                  </div>
                </div>
              </CardContent>
            </Card>

            <TokenBarChart daily={data.dailyTokens} />
          </div>

          <DailyTable daily={data.dailyTokens} />
          <ModelTable models={data.models} />
        </>
      )}

      {!loading && data.dailyTokens.length === 0 && (
        <Card>
          <CardContent className="py-12">
            <div className="flex flex-col items-center text-muted-foreground">
              <BarChart3 className="h-8 w-8 mb-3 opacity-40" />
              <p className="text-sm font-medium">No usage data found.</p>
              <p className="text-xs mt-1 text-muted">Start a session to generate analytics.</p>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

export default AnalyticsPage;
