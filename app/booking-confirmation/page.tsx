import type { Metadata } from "next";
import { ConfirmationView } from "./view";

export const metadata: Metadata = {
  title: "예약 확인",
  referrer: "no-referrer",
  robots: { index: false, follow: false },
};

export default function ConfirmationPage() {
  return <ConfirmationView />;
}
