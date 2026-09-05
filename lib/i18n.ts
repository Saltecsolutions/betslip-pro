export type Locale = "sw" | "en";

export const messages = {
  sw: {
    tagline: "Soko la wataalamu wa predictions za michezo",
    hero: "Gundua tipsters waliothibitishwa. Linganisha performance. Nunua predictions kwa uwazi.",
    getStarted: "Anza Sasa",
    becomeTipster: "Kuwa Tipster",
    advertise: "Tangaza Betslip Pro",
    verified: "Tipster Aliyethibitishwa",
    disclaimer: "Predictions si ushindi wa uhakika. Bet responsibly. 18+.",
  },
  en: {
    tagline: "The marketplace for sports prediction experts",
    hero: "Discover verified tipsters. Compare real performance. Buy predictions with transparency.",
    getStarted: "Get Started",
    becomeTipster: "Become a Tipster",
    advertise: "Advertise on Betslip Pro",
    verified: "Verified Tipster",
    disclaimer: "Predictions are not guaranteed wins. Bet responsibly. 18+.",
  },
} as const;
