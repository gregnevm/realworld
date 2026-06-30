/* RealWorld — logistics.js : inter-map convoys between real-world regions */
(function (RW) {
  "use strict";

  // candidate real-world trade hubs (lat, lon). Home is the player's spawn.
  const HUBS = [
    { name: "Київ", lat: 50.4501, lon: 30.5234 },
    { name: "Львів", lat: 49.8397, lon: 24.0297 },
    { name: "Одеса", lat: 46.4825, lon: 30.7233 },
    { name: "Харків", lat: 49.9935, lon: 36.2304 },
    { name: "Варшава", lat: 52.2297, lon: 21.0122 },
    { name: "Краків", lat: 50.0647, lon: 19.9450 },
    { name: "Кишинів", lat: 47.0105, lon: 28.8638 }
  ];

  // what each outpost trades: send `buys` -> receive `sells` at `rate` (sent per 1 received)
  const OFFERS = [
    { buys: "wood", sells: "components", rate: 6 },
    { buys: "food", sells: "scrap", rate: 1 },
    { buys: "stone", sells: "food", rate: 1 }
  ];

  RW.initRegions = function (G) {
    const home = { name: G.map.placeName || "Поселення", lat: G.map.lat, lon: G.map.lon, home: true };
    // pick 3 nearest distinct hubs
    const ranked = HUBS
      .map(hb => ({ ...hb, d: RW.haversineKm(home.lat, home.lon, hb.lat, hb.lon) }))
      .filter(hb => hb.d > 8)
      .sort((a, b) => a.d - b.d)
      .slice(0, 3);
    G.regions = [home, ...ranked.map((hb, i) => ({ ...hb, offer: OFFERS[i % OFFERS.length] }))];
    G.convoys = G.convoys || [];
  };

  RW.dispatchConvoy = function (G, hubIndex, sendRes, sendAmt) {
    const hub = G.regions[hubIndex];
    if (!hub || hub.home) return { ok: false, msg: "Невірний пункт призначення." };
    sendAmt = Math.max(1, Math.floor(sendAmt));
    if ((G.base.stock[sendRes] || 0) < sendAmt) return { ok: false, msg: "Недостатньо ресурсу на складі." };
    if (sendRes !== hub.offer.buys) return { ok: false, msg: hub.name + " приймає лише " + RW.RES[hub.offer.buys].label + "." };

    G.base.stock[sendRes] -= sendAmt;
    const recvRes = hub.offer.sells;
    const recvAmt = Math.max(1, Math.floor(sendAmt / hub.offer.rate));
    const dist = RW.haversineKm(G.regions[0].lat, G.regions[0].lon, hub.lat, hub.lon);
    const oneWay = RW.clamp(dist * 0.045, 7, 55);

    const convoy = {
      id: G.convoySeq = (G.convoySeq || 0) + 1,
      hubIndex, hubName: hub.name,
      sendRes, sendAmt, recvRes, recvAmt,
      phase: "out", t: 0, dur: oneWay, dist: Math.round(dist), ambushed: false
    };
    G.convoys.push(convoy);
    RW.log(G, `🚚 Конвой #${convoy.id} вирушив до ${hub.name} (${convoy.dist} км) з ${sendAmt} ${RW.RES[sendRes].icon}.`, "good");
    return { ok: true };
  };

  RW.updateConvoys = function (G, dt) {
    for (let k = G.convoys.length - 1; k >= 0; k--) {
      const c = G.convoys[k];
      c.t += dt;
      if (c.t < c.dur) continue;
      if (c.phase === "out") {
        c.phase = "back"; c.t = 0;
        RW.log(G, `🔄 Конвой #${c.id} обміняв вантаж у ${c.hubName}, везе ${c.recvAmt} ${RW.RES[c.recvRes].icon} назад.`);
        // ambush roll on the return leg
        if (Math.random() < 0.25) {
          c.ambushed = true;
          const lost = Math.max(1, Math.round(c.recvAmt * (0.3 + Math.random() * 0.4)));
          c.recvAmt = Math.max(0, c.recvAmt - lost);
          RW.log(G, `⚔ Засідка на конвой #${c.id}! Відбито ${lost} ${RW.RES[c.recvRes].icon}.`, "bad");
        }
      } else {
        // arrived home
        RW.deposit(G, c.recvRes, c.recvAmt);
        RW.log(G, `📦 Конвой #${c.id} повернувся: +${c.recvAmt} ${RW.RES[c.recvRes].icon} на склад.`, "good");
        G.convoys.splice(k, 1);
      }
    }
  };

})(window.RW);
