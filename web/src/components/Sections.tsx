import QRCode from "qrcode";
import { useEffect, useState } from "react";
import type { Comparison, ServiceId, ServiceInfo, Stats, Unit } from "../api/types";
import { formatDistance, formatEta, plural } from "../lib/format";
import { SERVICE_ORDER, SERVICE_STYLES, shortCategory } from "../lib/services";
import { Apple, ArrowRight, Phone, Pin, Play, Qr, ServiceIcon } from "./Icons";
import { Logo } from "./Brand";

export const APP_URL = "/app/citizen/";
export const RESPONDER_URL = "/app/responder/";

export function Header({ city }: { city: string }) {
  return (
    <header className="header">
      <Logo />
      <nav className="header__nav" aria-label="Основная навигация">
        <a href="#about">О сервисе</a>
        <a href="#services">Экстренные службы</a>
        <a href="#how">Как это работает</a>
        <a href="#app">Приложение</a>
        <a href="#faq">Вопросы</a>
      </nav>
      <span className="header__city"><Pin size={16} /> {city}</span>
      <a className="btn btn--primary" href={APP_URL}>Открыть приложение <ArrowRight /></a>
    </header>
  );
}

export function StoreBadges() {
  // Native builds are not published yet; the badges lead to the web build of the same app.
  return (
    <div className="stores">
      <a className="store" href={APP_URL} title="Нативная сборка ещё не опубликована — откроется веб-версия приложения">
        <Apple /><span><small>Скоро в</small>App Store</span>
      </a>
      <a className="store" href={APP_URL} title="Нативная сборка ещё не опубликована — откроется веб-версия приложения">
        <Play /><span><small>Скоро в</small>Google Play</span>
      </a>
    </div>
  );
}

export function QrCode({ url, size = 148 }: { url: string; size?: number }) {
  const [src, setSrc] = useState("");
  useEffect(() => {
    QRCode.toDataURL(url, { margin: 1, width: size * 2, color: { dark: "#0F1E3D", light: "#FFFFFF" } })
      .then(setSrc)
      .catch(() => setSrc(""));
  }, [url, size]);
  return src ? <img className="qr" src={src} width={size} height={size} alt={`QR-код: ${url}`} /> : <div className="qr qr--empty" style={{ width: size, height: size }} />;
}

export function PhoneFrame({ src, alt, tilt = false }: { src: string; alt: string; tilt?: boolean }) {
  return (
    <div className={`phone${tilt ? " phone--tilt" : ""}`}>
      <div className="phone__screen"><img src={src} alt={alt} loading="lazy" /></div>
    </div>
  );
}

export function NearestUnits({ units, loading, onPick }: { units: Unit[]; loading: boolean; onPick: (unit: Unit) => void }) {
  return (
    <section className="panel" aria-labelledby="nearest-title">
      <div className="panel__head">
        <h2 id="nearest-title">Ближайшие подразделения</h2>
        <a href="#top" className="link">Смотреть все <ArrowRight size={14} /></a>
      </div>
      <div className="nearest">
        {loading && [0, 1, 2].map((i) => <div key={i} className="unit-card unit-card--skeleton" />)}
        {!loading && units.length === 0 && <p className="muted">Свободных экипажей рядом сейчас нет.</p>}
        {units.map((unit) => (
          <button key={unit.id} className="unit-card" onClick={() => onPick(unit)}>
            <img src={`/images/${unit.photo}_thumb.jpg`} alt="" loading="lazy" />
            <span className="unit-card__body">
              <span className="unit-card__title">
                <i className={`dot dot--${unit.service}`}><ServiceIcon service={unit.service} size={12} /></i>
                <b>{unit.name}</b>
              </span>
              <small>{SERVICE_STYLES[unit.service].short}</small>
              <span className="unit-card__metrics">
                <Pin size={13} /> {formatDistance(unit.distance_m)} • {formatEta(unit.eta_s)}
              </span>
            </span>
            <span className="unit-card__go"><ArrowRight size={14} /></span>
          </button>
        ))}
      </div>
    </section>
  );
}

export function Categories({ catalog, stats }: { catalog: ServiceInfo[]; stats: Stats | null }) {
  return (
    <section className="panel" id="services" aria-labelledby="categories-title">
      <div className="panel__head">
        <h2 id="categories-title">Категории экстренных служб</h2>
        <a href="#how" className="link">Подробнее <ArrowRight size={14} /></a>
      </div>
      <div className="categories">
        {catalog.map((service) => {
          const live = stats?.services[service.id];
          return (
            <article key={service.id} className={`category category--${service.id}`}>
              <h3><i className={`dot dot--${service.id} dot--lg`}><ServiceIcon service={service.id} size={15} /></i>{service.title}</h3>
              <ul>
                {service.categories.map((c, i) => <li key={c.id} className={i === 0 ? "is-main" : ""} title={c.description}>{shortCategory(service.id, c.title)}</li>)}
              </ul>
              {live && <p className="category__live">{live.units_free} из {live.units} {plural(live.units, "экипажа", "экипажей", "экипажей")} свободно</p>}
            </article>
          );
        })}
      </div>
    </section>
  );
}

export function AppCta({ appUrl }: { appUrl: string }) {
  return (
    <section className="cta" id="app">
      <div className="cta__text">
        <h2>Для оформления вызова перейдите в приложение</h2>
        <p>Сайт помогает найти ближайшие подразделения и ознакомиться с доступными службами. Вызов оформляется в приложении Jardem.ai.</p>
        <a className="btn btn--primary" href={APP_URL}><Phone /> Перейти в приложение <ArrowRight /></a>
      </div>
      <div className="cta__qr">
        <QrCode url={appUrl} />
        <div>
          <b>Сканируйте QR-код, чтобы открыть приложение</b>
          <p>Камера телефона откроет Jardem.ai в браузере — установка не требуется.</p>
          <StoreBadges />
        </div>
      </div>
      <PhoneFrame src="/images/app-splash.png" alt="Экран приложения Jardem.ai" />
    </section>
  );
}

const STEPS = [
  { n: "1", title: "Вы описываете ситуацию", text: "Выбираете службу и категорию или пишете своими словами. Алгоритм разбора текста подсказывает категорию и срочность и показывает, каких сведений не хватает." },
  { n: "2", title: "Система подбирает экипаж", text: "Оптимизатор сравнивает все свободные экипажи: время в пути с учётом пробок, нужное оснащение бригады и то, чтобы район не остался без прикрытия." },
  { n: "3", title: "Экипаж едет по лучшему маршруту", text: "Маршрут строится по дорожному графу Алматы и перестраивается при заторах и перекрытиях. Вы видите статус, машину на карте и время прибытия." },
];

export function HowItWorks() {
  return (
    <section className="block" id="how">
      <p className="eyebrow">Как это работает</p>
      <h2>От обращения до прибытия — три шага</h2>
      <div className="steps">
        {STEPS.map((s) => (
          <article key={s.n} className="step"><span>{s.n}</span><h3>{s.title}</h3><p>{s.text}</p></article>
        ))}
      </div>
    </section>
  );
}

const STRATEGY_LABEL: Record<keyof Comparison["picks"], { title: string; text: string }> = {
  nearest: { title: "Ближайший по расстоянию", text: "Базовый подход: по прямой, без учёта дорог и пробок." },
  min_eta: { title: "Минимальное время в пути", text: "Учитывает дороги и пробки, но не думает о соседних вызовах." },
  jardem: { title: "Оптимизатор Jardem", text: "Время, приоритет вызова, оснащение бригады и покрытие районов." },
};

export function Optimizer({ comparison, service, loading }: { comparison: Comparison | null; service: ServiceId; loading: boolean }) {
  const byId = new Map(comparison?.candidates.map((c) => [c.id, c]));
  return (
    <section className="block" id="about">
      <p className="eyebrow">О сервисе</p>
      <h2>Не «кто ближе», а «кто приедет быстрее — и кого лучше оставить в резерве»</h2>
      <p className="lead">
        Ниже — живой расчёт для точки, выбранной на карте, и службы «{SERVICE_STYLES[service].short}».
        Три стратегии получают одни и те же экипажи и дорожную обстановку.
      </p>
      <div className="strategies">
        {(Object.keys(STRATEGY_LABEL) as (keyof Comparison["picks"])[]).map((key) => {
          const picked = comparison?.picks[key].map((id) => byId.get(id)).filter(Boolean) ?? [];
          return (
            <article key={key} className={`strategy${key === "jardem" ? " strategy--ours" : ""}`}>
              <h3>{STRATEGY_LABEL[key].title}</h3>
              <p>{STRATEGY_LABEL[key].text}</p>
              {loading && <div className="strategy__pick strategy__pick--skeleton" />}
              {!loading && picked.length === 0 && <div className="strategy__pick muted">Нет подходящего свободного экипажа</div>}
              {!loading && picked.map((unit) => unit && (
                <div key={unit.id} className="strategy__pick">
                  <b>{unit.name} <small className="muted">{unit.plate}</small></b>
                  <span>{formatDistance(unit.distance_m)} • {formatEta(unit.eta_s)}</span>
                </div>
              ))}
            </article>
          );
        })}
      </div>
      {comparison && comparison.candidates.length > 0 && (
        <div className="table-wrap">
          <table className="candidates">
            <caption>Кандидаты по убыванию предпочтения оптимизатора</caption>
            <thead><tr><th>Экипаж</th><th>По прямой</th><th>В пути</th><th>Потеря покрытия</th><th>Избыточное оснащение</th><th>Итоговая стоимость</th></tr></thead>
            <tbody>
              {comparison.candidates.slice(0, 5).map((c) => (
                <tr key={c.id} className={comparison.picks.jardem.includes(c.id) ? "is-picked" : ""}>
                  <td>{c.name}<small>{c.plate}</small></td><td>{formatDistance(c.distance_m)}</td><td>{formatEta(c.eta_s)}</td>
                  <td>{c.coverage_loss_s > 0 ? `+${c.coverage_loss_s} с` : "—"}</td>
                  <td>{c.overqualified > 0 ? "да" : "—"}</td><td>{c.cost}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

export function LiveStats({ stats, online }: { stats: Stats | null; online: boolean }) {
  const units = stats ? SERVICE_ORDER.reduce((n, s) => n + stats.services[s].units, 0) : null;
  const items = [
    { value: units ?? "—", label: "экипажей на линии" },
    { value: stats?.departments ?? "—", label: "подразделения на карте" },
    { value: stats?.active_incidents ?? "—", label: "вызовов в работе" },
    { value: stats?.mean_arrival_s ? formatEta(stats.mean_arrival_s) : "—", label: "среднее время прибытия" },
  ];
  return (
    <section className="stats" aria-label="Состояние платформы">
      <span className={`stats__status${online ? " is-on" : ""}`}>{online ? "Данные в реальном времени" : "Подключение…"}</span>
      {items.map((item) => <div key={item.label}><b>{item.value}</b><span>{item.label}</span></div>)}
    </section>
  );
}

export function ForResponders() {
  return (
    <section className="block responders">
      <div>
        <p className="eyebrow">Для служб</p>
        <h2>Приложение экипажа: вызов, маршрут и связь с диспетчером</h2>
        <p className="lead">Бригада получает назначение, видит маршрут с учётом пробок, отмечает этапы «В пути → На месте → Отработан» и сообщает о перекрытиях — эти данные сразу учитываются в маршрутах других экипажей.</p>
        <a className="btn btn--ghost" href={RESPONDER_URL}>Открыть приложение экипажа <ArrowRight /></a>
        <p className="muted small">Демо-вход: логин smp7, PIN 1234 — бригада «СМП №7».</p>
      </div>
      <PhoneFrame src="/images/responder-home.png" alt="Экран приложения экипажа" />
    </section>
  );
}

const FAQ = [
  { q: "Это настоящая служба экстренной помощи?", a: "Нет. Jardem.ai — демонстрационная платформа дипломного проекта. Экипажи, вызовы и пробки смоделированы. В реальной экстренной ситуации звоните 112 (или 103, 102, 101)." },
  { q: "Откуда данные на карте?", a: "Дорожная сеть и адреса пожарных частей и отделений полиции — из OpenStreetMap. Расположение подстанций скорой и баз спасателей приблизительное. Движение экипажей и дорожная обстановка рассчитываются симулятором." },
  { q: "Как выбирается экипаж?", a: "Для всех открытых вызовов одновременно решается задача о назначениях: минимизируется время в пути, взвешенное по срочности, с штрафами за потерю покрытия района и за отправку специализированной бригады на рядовой вызов." },
  { q: "Пробки настоящие?", a: "Нет, это модель: суточный профиль загрузки, очаги заторов и перекрытия. Реальный сигнал в ней один — скорость экипажей, которую передаёт приложение службы." },
  { q: "Что нужно, чтобы это заработало в городе?", a: "Соглашения со службами и доступ к их данным. Платформа рассчитана на роль дополнительного цифрового канала и системы поддержки решений диспетчера — не на замену 112." },
];

export function Faq() {
  return (
    <section className="block" id="faq">
      <p className="eyebrow">Вопросы</p>
      <h2>Коротко о главном</h2>
      <div className="faq">
        {FAQ.map((item, i) => <details key={item.q} open={i === 0}><summary>{item.q}</summary><p>{item.a}</p></details>)}
      </div>
    </section>
  );
}

const CREDITS = [
  "Панорамы Алматы — Kalpak Travel, Irene2005 (CC BY 2.0)",
  "Скорая, полиция, пожарные, спасатели — Nikolai Bulykin, Nurken (CC BY-SA 4.0), Peretz Partensky (CC BY-SA 2.0), «Аппарат Правления» (CC0)",
  "Источник фотографий — Wikimedia Commons; изображения уменьшены и обрезаны",
  "Карта — © OpenStreetMap contributors, OpenFreeMap, OpenMapTiles",
];

export function Footer() {
  return (
    <footer className="footer">
      <div className="footer__row">
        <Logo compact />
        <nav aria-label="Нижняя навигация">
          <a href="#about">О сервисе</a><a href="#services">Экстренные службы</a><a href="#app">Приложение</a>
          <a href="#faq">Частые вопросы</a><a href={RESPONDER_URL}>Для служб</a><a href="/api/docs">API</a>
        </nav>
        <span className="footer__copy">© 2026 Jardem.ai · дипломный проект</span>
      </div>
      <details className="footer__credits">
        <summary>Фотографии и карта</summary>
        <ul>{CREDITS.map((c) => <li key={c}>{c}</li>)}</ul>
      </details>
    </footer>
  );
}

export function QrButton() {
  return <a className="btn btn--ghost" href="#app"><Qr /> Открыть по QR</a>;
}
