import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { validSlug } from "../../../lib/booking/types";
import { BookingForm } from "./booking-form";

export const metadata: Metadata = {
  title: "고객 예약",
  referrer: "no-referrer",
  robots: { index: false, follow: false },
};

export default async function BookingPage({ params }: PageProps<"/book/[slug]">) {
  const { slug } = await params;
  if (!validSlug(slug)) notFound();
  return <BookingForm key={slug} slug={slug} />;
}
