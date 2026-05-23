const colors = {
  shortage: "#dc2626",
  surplus: "#1f9d55",
  balanced: "#74808a",
};

const map = L.map("map", {
  preferCanvas: true,
}).setView([36.3504, 127.3845], 12);

L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19,
  attribution: "&copy; OpenStreetMap contributors",
}).addTo(map);

const markerLayer = L.layerGroup().addTo(map);
const markerById = new Map();
let allStations = [];
let currentFilter = "all";

const numberFormat = new Intl.NumberFormat("ko-KR");

function statusLabel(status) {
  if (status === "shortage") return "자전거 부족";
  if (status === "surplus") return "자전거 과잉";
  return "균형";
}

function markerRadius(station) {
  return Math.max(5, Math.min(20, 5 + Math.sqrt(Math.abs(station.imbalance)) / 2.1));
}

function popupHtml(station) {
  return `
    <strong>${station.name}</strong><br>
    ${station.gu || ""} ${station.dong || ""}<br>
    상태: <b>${statusLabel(station.status)}</b><br>
    대여 횟수: ${numberFormat.format(station.rentals)}<br>
    반납 횟수: ${numberFormat.format(station.returns)}<br>
    쏠림 점수: ${numberFormat.format(station.imbalance)}
  `;
}

function visibleStations() {
  if (currentFilter === "all") return allStations;
  return allStations.filter((station) => station.status === currentFilter);
}

function drawMarkers() {
  markerLayer.clearLayers();
  markerById.clear();

  visibleStations().forEach((station) => {
    const marker = L.circleMarker([station.lat, station.lng], {
      radius: markerRadius(station),
      color: colors[station.status],
      fillColor: colors[station.status],
      fillOpacity: station.status === "balanced" ? 0.42 : 0.72,
      opacity: 0.95,
      weight: station.status === "balanced" ? 1 : 2,
    })
      .bindPopup(popupHtml(station))
      .addTo(markerLayer);

    markerById.set(station.id, marker);
  });
}

function setText(id, value) {
  document.getElementById(id).textContent = numberFormat.format(value);
}

function renderStats(summary) {
  setText("stationCount", summary.stationCount);
  setText("tripCount", summary.totalTrips);
  setText("shortageCount", summary.shortageCount);
  setText("surplusCount", summary.surplusCount);
}

function renderRankList(id, stations) {
  const list = document.getElementById(id);
  list.innerHTML = "";

  stations.slice(0, 8).forEach((station) => {
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.innerHTML = `
      <span class="rank-name">${station.name}</span>
      <span class="rank-meta">${station.gu || ""} ${station.dong || ""} · 쏠림 점수 ${numberFormat.format(station.imbalance)}</span>
    `;
    button.addEventListener("click", () => focusStation(station));
    item.appendChild(button);
    list.appendChild(item);
  });
}

function focusStation(station) {
  currentFilter = "all";
  document.querySelectorAll(".filter-button").forEach((button) => {
    button.classList.toggle("active", button.dataset.filter === "all");
  });
  drawMarkers();
  map.setView([station.lat, station.lng], 15, { animate: true });
  const marker = markerById.get(station.id);
  if (marker) marker.openPopup();
}

function initFilters() {
  document.querySelectorAll(".filter-button").forEach((button) => {
    button.addEventListener("click", () => {
      currentFilter = button.dataset.filter;
      document.querySelectorAll(".filter-button").forEach((item) => {
        item.classList.toggle("active", item === button);
      });
      drawMarkers();
    });
  });
}

function boot(summary) {
    allStations = summary.stations;
    renderStats(summary);
    renderRankList(
      "shortageList",
      allStations.filter((station) => station.status === "shortage").sort((a, b) => a.imbalance - b.imbalance),
    );
    renderRankList(
      "surplusList",
      allStations.filter((station) => station.status === "surplus").sort((a, b) => b.imbalance - a.imbalance),
    );
    initFilters();
    drawMarkers();
}

if (window.TASHU_DATA) {
  boot(window.TASHU_DATA);
} else {
  fetch("./data/stations.json")
    .then((response) => {
      if (!response.ok) throw new Error("요약 데이터를 불러오지 못했습니다.");
      return response.json();
    })
    .then(boot)
    .catch((error) => {
      document.getElementById("map").innerHTML = `<p class="map-error">${error.message}</p>`;
    });
}
