// The menu bar in the hero mock read "Mon 2:41 AM" on every visit, in every
// language, for as long as the page has existed. It is a photograph of an app
// whose whole subject is time, and its clock was the one detail a reader could
// hold against the corner of their own screen — so it was also the one detail
// the picture was always wrong about.
//
// This is the first script softcap.app has served. `script-src 'self'` was
// added to the Content-Security-Policy for this file and nothing else, which is
// why it is a file and not three lines inside the document: an inline script
// would need `unsafe-inline` in the same breath, and that is a different policy
// to live under for the sake of one saved request.
//
// It writes three time-shaped places in one mock and touches nothing else. The
// markup still ships the frozen scene, so with the script blocked, absent or
// switched off the page is exactly what it was — which is why every element
// here is found and never created.
(() => {
  "use strict";

  const menuTime = document.querySelector('[data-clock="menubar"]');
  const windowTime = document.querySelector('[data-clock="window"]');
  const staleDate = document.querySelector('[data-clock="stale"]');
  if (!menuTime && !windowTime && !staleDate) return;

  // Western digits, asked for rather than defaulted to: the rest of this mock
  // counts in them — the percentages, "41m", the chart — and Arabic and Bengali
  // would each be given their own numerals, leaving one scene counting in two
  // alphabets. A malformed `lang` is the only way `Intl` throws here, and the
  // page is worth more than the locale.
  const locale = (document.documentElement.lang || "en") + "-u-nu-latn";
  const fmt = (options) => {
    try { return new Intl.DateTimeFormat(locale, options); }
    catch (e) { return new Intl.DateTimeFormat("en", options); }
  };

  const time = fmt({ hour: "numeric", minute: "2-digit" });
  const weekday = fmt({ weekday: "short" });
  // The markup wrote `2:41&nbsp;AM` by hand and that space was doing work: it
  // keeps the day period on the hour's line. Which space `Intl` puts there is
  // the engine's business — current ICU uses U+202F, which does not break, and
  // an older one uses an ordinary space, which does. Made non-breaking here so
  // it is not left to whichever browser arrives.
  const clock = (date) => time.format(date).replace(/\s/g, "\u00a0");
  // "Data from" is English on all ten pages — the one label in this mock that
  // was never translated — so its date is formatted to match the words next to
  // it rather than the page around them.
  //
  // "28 Aug", which is what stood here, is a day then three letters of month.
  // `en-GB` puts them in that order and spells September "Sept"; `en-US` spells
  // it "Sep" and leads with the month. Neither is the shape that was here, so
  // the American parts are taken and laid out in the British order.
  const monthFirst = new Intl.DateTimeFormat("en-US", { day: "numeric", month: "short" });
  const shortDate = (date) => {
    const parts = monthFirst.formatToParts(date);
    const part = (type) => (parts.find((p) => p.type === type) || {}).value || "";
    return part("day") + " " + part("month");
  };

  // Three days is the whole point of that tag: one row whose reading stopped
  // arriving, beside rows that are current. Twenty-two days, which is what
  // "28 Aug" had quietly become, reads as a broken page rather than as the
  // feature it is there to show.
  const STALE_DAYS = 3;

  const paint = () => {
    const now = new Date();
    if (menuTime) {
      // macOS capitalises the weekday; `Intl` hands back "пн" and "lun.". A
      // no-op in the scripts that have no cases to change.
      const name = weekday.format(now);
      menuTime.textContent =
        name.charAt(0).toUpperCase() + name.slice(1) + " " + clock(now);
    }
    if (windowTime) windowTime.textContent = clock(now);
    if (staleDate) {
      const then = new Date(now);
      then.setDate(then.getDate() - STALE_DAYS);
      staleDate.textContent = shortDate(then);
    }
  };

  paint();

  // On the minute, rather than every sixty seconds from whenever the page
  // happened to load. The mock sits a few centimetres below a real menu bar,
  // and two clocks turning over half a minute apart is the kind of thing that
  // gets noticed without ever being named.
  let timer = 0;
  const schedule = () => {
    clearTimeout(timer);
    timer = setTimeout(
      () => { paint(); schedule(); },
      (60 - new Date().getSeconds()) * 1000 + 50);
  };
  schedule();

  // A hidden tab is throttled and a sleeping machine stops the timer outright;
  // either way the clock comes back wrong and stays wrong until a tick that may
  // be minutes away. Repaint on the way back in.
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) { paint(); schedule(); }
  });
})();
