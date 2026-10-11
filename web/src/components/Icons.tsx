import type { ServiceId } from "../api/types";

type IconProps = { size?: number; className?: string };

const base = (size: number) => ({ width: size, height: size, viewBox: "0 0 24 24", "aria-hidden": true }) as const;

export function ServiceIcon({ service, size = 18 }: { service: ServiceId; size?: number }) {
  switch (service) {
    case "ambulance":
      return <svg {...base(size)} fill="currentColor"><path d="M9.5 3h5v6.500H21v5h-6.500V21h-5v-6.500H3v-5h6.500z" /></svg>;
    case "police":
      return (
        <svg {...base(size)} fill="currentColor">
          <path d="M12 2l8 3v6.200c0 5-3.300 8.700-8 10.800-4.700-2.100-8-5.800-8-10.800V5l8-3zm0 3.200L7 7.100v4.100c0 3.300 1.900 5.800 5 7.500 3.100-1.700 5-4.200 5-7.500V7.100l-5-1.900z" />
        </svg>
      );
    case "fire":
      return (
        <svg {...base(size)} fill="currentColor">
          <path d="M13 2c.6 4 5.500 6.200 5.500 12A6.500 6.500 0 0 1 12 20.500 6.500 6.500 0 0 1 5.500 14c0-2.900 1.500-4.800 3-6.700.500 2 1.400 3 2.700 3.200C11 7.500 11.300 4.500 13 2zm-1 10.500c-1.500 1.600-2.300 2.700-2.300 4a2.300 2.300 0 0 0 4.600 0c0-1.300-.8-2.400-2.300-4z" />
        </svg>
      );
    default:
      return (
        <svg {...base(size)} fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
          <circle cx="12" cy="12" r="8.500" /><circle cx="12" cy="12" r="3.400" />
          <path d="M6 6l3.600 3.600M18 6l-3.600 3.600M6 18l3.600-3.600M18 18l-3.600-3.600" />
        </svg>
      );
  }
}

const stroke = (size: number) => ({ ...base(size), fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round", strokeLinejoin: "round" }) as const;

export const ArrowRight = ({ size = 18 }: IconProps) => <svg {...stroke(size)}><path d="M5 12h14M13 6l6 6-6 6" /></svg>;
export const Phone = ({ size = 18 }: IconProps) => (
  <svg {...base(size)} fill="currentColor"><path d="M6.600 2.800c.7-.7 1.900-.7 2.600.100l2 2.500c.6.700.5 1.700-.100 2.300L9.800 9c1.200 2.300 2.900 4 5.200 5.200l1.300-1.300c.6-.6 1.600-.7 2.300-.100l2.500 2c.8.700.9 1.900.100 2.600l-1.400 1.400c-1.100 1.100-2.700 1.500-4.100 1C10 18 6 14 4.200 8.300c-.5-1.400-.1-3 1-4.100l1.400-1.400z" /></svg>
);
export const Pin = ({ size = 18 }: IconProps) => <svg {...stroke(size)}><path d="M12 21s7-6.200 7-11.500A7 7 0 0 0 5 9.500C5 14.800 12 21 12 21z" /><circle cx="12" cy="9.500" r="2.500" /></svg>;
export const Clock = ({ size = 16 }: IconProps) => <svg {...stroke(size)}><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>;
export const Search = ({ size = 18 }: IconProps) => <svg {...stroke(size)}><circle cx="11" cy="11" r="7" /><path d="M20 20l-3.500-3.500" /></svg>;
export const Locate = ({ size = 18 }: IconProps) => <svg {...stroke(size)}><path d="M20 4L4 10.500l7 2.500 2.500 7L20 4z" /></svg>;
export const Layers = ({ size = 18 }: IconProps) => <svg {...stroke(size)}><path d="M12 3l9 5-9 5-9-5 9-5zM3 13l9 5 9-5" /></svg>;
export const Plus = ({ size = 18 }: IconProps) => <svg {...stroke(size)}><path d="M12 5v14M5 12h14" /></svg>;
export const Minus = ({ size = 18 }: IconProps) => <svg {...stroke(size)}><path d="M5 12h14" /></svg>;
export const Chevron = ({ size = 16 }: IconProps) => <svg {...stroke(size)}><path d="M9 6l6 6-6 6" /></svg>;
export const Qr = ({ size = 20 }: IconProps) => (
  <svg {...stroke(size)}><rect x="3" y="3" width="7" height="7" rx="1" /><rect x="14" y="3" width="7" height="7" rx="1" /><rect x="3" y="14" width="7" height="7" rx="1" /><path d="M14 14h3v3h-3zM20 14v.01M14 20v.01M20 20v.01M17 17h3v3" /></svg>
);
export const Apple = ({ size = 22 }: IconProps) => (
  <svg {...base(size)} fill="currentColor"><path d="M16.400 12.600c0-2.300 1.900-3.400 2-3.500-1.100-1.600-2.800-1.800-3.400-1.800-1.400-.1-2.800.9-3.500.9-.7 0-1.800-.8-3-.8-1.500 0-3 .9-3.800 2.300-1.600 2.800-.4 7 1.200 9.300.8 1.100 1.700 2.400 2.900 2.300 1.200 0 1.600-.7 3-.7s1.800.7 3 .7c1.300 0 2.100-1.100 2.800-2.300.9-1.300 1.300-2.600 1.300-2.600s-2.500-1-2.500-3.800zM14.100 5.800c.6-.8 1.100-1.900 1-3-.9 0-2.100.6-2.700 1.400-.6.7-1.100 1.800-1 2.900 1 .1 2.100-.5 2.700-1.300z" /></svg>
);
export const Play = ({ size = 22 }: IconProps) => (
  <svg {...base(size)} fill="currentColor"><path d="M4 3.300v17.400c0 .6.6.9 1.100.6l14.800-8.700c.5-.3.5-1 0-1.200L5.100 2.700C4.600 2.400 4 2.700 4 3.300z" /></svg>
);
