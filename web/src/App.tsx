import { useCallback, useEffect, useMemo, useState } from "react";
import { api } from "./api/client";
import type { Comparison, Position, ServiceId, Unit } from "./api/types";
import { ArrowRight, Phone } from "./components/Icons";
import { LiveMap } from "./components/LiveMap";
import {
  APP_URL, AppCta, Categories, Faq, Footer, ForResponders, Header, HowItWorks, LiveStats,
  NearestUnits, Optimizer, PhoneFrame, QrButton, StoreBadges,
} from "./components/Sections";
import { useLive } from "./hooks/useLive";
import { insideBbox } from "./lib/geo";
import { nearestPerService } from "./lib/services";

const ROUTE_REFRESH_MS = 8000;

export function App() {
  const live = useLive();
  const { point, setPoint, units, meta } = live;
  const [service, setService] = useState<ServiceId>("ambulance");
  const [route, setRoute] = useState<Position[] | null>(null);
  const [routed, setRouted] = useState<Unit | null>(null);
  const [comparison, setComparison] = useState<Comparison | null>(null);
  const [comparing, setComparing] = useState(true);
  const [notice, setNotice] = useState<string | null>(null);

  const nearest = useMemo(() => nearestPerService(units), [units]);
  const candidate = nearest.find((u) => u.service === service) ?? null;
  const candidateId = candidate?.id ?? null;

  // Road route and exact ETA from the highlighted unit to the chosen point.
  useEffect(() => {
    if (!candidateId) {
      setRoute(null);
      setRouted(null);
      return;
    }
    let cancelled = false;
    const load = () =>
      api.unitRoute(candidateId, point.lat, point.lon)
        .then((unit) => {
          if (cancelled) return;
          setRoute(unit.route ?? null);
          setRouted(unit);
        })
        .catch(() => undefined);
    void load();
    const timer = setInterval(load, ROUTE_REFRESH_MS);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [candidateId, point.lat, point.lon]);

  const defaultCategory = live.catalog.find((s) => s.id === service)?.categories[0]?.id;
  useEffect(() => {
    if (!defaultCategory) return;
    let cancelled = false;
    setComparing(true);
    api.compare(defaultCategory, point.lat, point.lon)
      .then((result) => !cancelled && setComparison(result))
      .catch(() => !cancelled && setComparison(null))
      .finally(() => !cancelled && setComparing(false));
    return () => {
      cancelled = true;
    };
  }, [defaultCategory, point.lat, point.lon]);

  const locate = useCallback(() => {
    if (!navigator.geolocation) {
      setNotice("Браузер не поддерживает геолокацию. Выберите точку нажатием на карту.");
      return;
    }
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        if (meta && !insideBbox(coords.latitude, coords.longitude, meta.bbox)) {
          setNotice("Вы находитесь за пределами Алматы — на карте оставлен демо-адрес.");
          return;
        }
        setNotice(null);
        setPoint(coords.latitude, coords.longitude);
      },
      () => setNotice("Не удалось определить местоположение. Выберите точку нажатием на карту."),
      { enableHighAccuracy: true, timeout: 8000 },
    );
  }, [meta, setPoint]);

  const highlight = candidate && routed?.id === candidate.id
    ? { ...candidate, distance_m: routed.distance_m, eta_s: routed.eta_s }
    : candidate;
  const cards = nearest.filter((u) => u.service !== "rescue").slice(0, 3);

  return (
    <div className="page" id="top">
      <div className="demo-bar" role="note">
        <span>{meta?.disclaimer ?? "Демонстрационная платформа. В реальной экстренной ситуации звоните 112."}</span>
        <a href="tel:112"><Phone size={14} /> 112</a>
      </div>
      <div className="shell">
        <Header city={meta?.city ?? "Алматы"} />

        <section className="hero">
          <div className="hero__text">
            <h1>Экстренные службы ближе, чем кажется</h1>
            <p>
              Найдите ближайшие станции скорой помощи, полиции, пожарных и спасателей на карте. Изучите
              доступные службы — для оформления вызова перейдите в приложение Jardem.ai.
            </p>
            <div className="hero__actions">
              <a className="btn btn--primary btn--lg" href={APP_URL}><Phone /> Перейти в приложение <ArrowRight /></a>
              <QrButton />
            </div>
            <StoreBadges />
          </div>
          <div className="hero__phone">
            <PhoneFrame src="/images/app-home.png" alt="Карта служб в приложении Jardem.ai" tilt />
          </div>
          <div className="hero__map">
            <LiveMap units={units} traffic={live.traffic} point={point} onPoint={setPoint} service={service}
              onService={setService} highlight={highlight} route={route} onLocate={locate} />
          </div>
        </section>

        {(notice || live.error) && <p className="notice" role="status">{notice ?? live.error}</p>}

        <div className="row">
          <NearestUnits units={cards} loading={units.length === 0 && !live.error} onPick={(u) => setService(u.service)} />
          <Categories catalog={live.catalog} stats={live.stats} />
        </div>

        <AppCta appUrl={meta?.app_url ?? new URL(APP_URL, location.origin).href} />
        <LiveStats stats={live.stats} online={live.online} />
        <HowItWorks />
        <Optimizer comparison={comparison} service={service} loading={comparing} />
        <ForResponders />
        <Faq />
        <Footer />
      </div>
    </div>
  );
}
