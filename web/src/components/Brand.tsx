export function Logo({ compact = false }: { compact?: boolean }) {
  return (
    <a className={`logo${compact ? " logo--compact" : ""}`} href="#top" aria-label="Jardem.ai — на главную">
      <img src="/brand/logo.svg" alt="" width={compact ? 40 : 56} height={compact ? 40 : 56} />
      <span className="logo__text">
        <span className="logo__name">Jardem.ai</span>
        <span className="logo__tag">Emergency aggregator platform</span>
      </span>
    </a>
  );
}
