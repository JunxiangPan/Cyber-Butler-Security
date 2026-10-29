"""Open-Meteo weather tools for 苏瑾言."""

from __future__ import annotations

import asyncio
import json
import re
from pathlib import Path

import requests
from astrbot import logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.star import Context, Star

SETTINGS_PATH = Path(__file__).with_name("settings.json")
GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

DEFAULT_SETTINGS = {
    "active": "新加坡",
    "cities": {
        "新加坡": {"latitude": 1.3521, "longitude": 103.8198},
        "上海": {"latitude": 31.2304, "longitude": 121.4737},
    },
}

WEATHER_CODES = {
    0: "晴",
    1: "晴间多云",
    2: "多云",
    3: "阴",
    45: "雾",
    48: "雾凇",
    51: "小毛毛雨",
    53: "毛毛雨",
    55: "大毛毛雨",
    61: "小雨",
    63: "中雨",
    65: "大雨",
    66: "冻雨",
    67: "强冻雨",
    71: "小雪",
    73: "中雪",
    75: "大雪",
    77: "雪粒",
    80: "小阵雨",
    81: "阵雨",
    82: "强阵雨",
    85: "小阵雪",
    86: "强阵雪",
    95: "雷暴",
    96: "雷暴伴冰雹",
    99: "强雷暴伴冰雹",
}


def _load_settings() -> dict:
    settings = json.loads(json.dumps(DEFAULT_SETTINGS, ensure_ascii=False))
    try:
        if SETTINGS_PATH.exists():
            raw = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                settings.update(raw)
                if isinstance(raw.get("cities"), dict):
                    settings["cities"].update(raw["cities"])
    except Exception as exc:
        logger.warning("[weather] settings load failed: %s", exc)
    return settings


def _save_settings(settings: dict) -> None:
    try:
        SETTINGS_PATH.write_text(
            json.dumps(settings, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except Exception as exc:
        logger.warning("[weather] settings save failed: %s", exc)


def _geocode(city: str) -> dict:
    """Return a city record from Open-Meteo geocoding."""
    response = requests.get(
        GEOCODE_URL,
        params={"name": city, "count": 1, "language": "zh", "format": "json"},
        timeout=15,
    )
    response.raise_for_status()
    results = (response.json() or {}).get("results") or []
    if not results:
        raise ValueError(f"找不到城市：{city}")
    item = results[0]
    return {
        "name": item.get("name") or city,
        "latitude": float(item["latitude"]),
        "longitude": float(item["longitude"]),
        "country": item.get("country") or "",
    }


def _weather_label(code: int | None) -> str:
    return WEATHER_CODES.get(int(code or 0), f"天气代码{code}")


def _format_weather(city: str, data: dict) -> str:
    current = data.get("current") or {}
    daily = data.get("daily") or {}
    lines = [
        f"{city}现在 {current.get('temperature_2m')}°C，"
        f"体感 {current.get('apparent_temperature')}°C，"
        f"{_weather_label(current.get('weather_code'))}，"
        f"湿度 {current.get('relative_humidity_2m')}%，"
        f"风 {current.get('wind_speed_10m')} km/h。"
    ]
    dates = daily.get("time") or []
    pops = daily.get("precipitation_probability_max") or []
    highs = daily.get("temperature_2m_max") or []
    lows = daily.get("temperature_2m_min") or []
    sums = daily.get("precipitation_sum") or []
    for index, date in enumerate(dates[:3]):
        try:
            label = "今天" if index == 0 else ("明天" if index == 1 else date[5:])
            lines.append(
                f"{label}：{lows[index]}~{highs[index]}°C，"
                f"{_weather_label((daily.get('weather_code') or [0])[index])}，"
                f"降雨概率 {pops[index]}%，预计 {sums[index]} mm。"
            )
        except (IndexError, TypeError):
            continue

    today_pop = float((pops[0] if pops else 0) or 0)
    today_sum = float((sums[0] if sums else 0) or 0)
    if today_pop >= 40 or today_sum > 0:
        lines.append("建议：今天有雨，出门带伞。")
    elif highs and float(highs[0]) >= 32:
        lines.append("建议：今天偏热，注意防晒补水。")
    else:
        lines.append("建议：今天降雨概率不高，正常出门就行。")
    return "\n".join(lines)


def _fetch_weather(latitude: float, longitude: float) -> dict:
    response = requests.get(
        FORECAST_URL,
        params={
            "latitude": latitude,
            "longitude": longitude,
            "current": (
                "temperature_2m,relative_humidity_2m,apparent_temperature,"
                "precipitation,weather_code,wind_speed_10m"
            ),
            "daily": (
                "weather_code,temperature_2m_max,temperature_2m_min,"
                "precipitation_probability_max,precipitation_sum"
            ),
            "timezone": "auto",
            "forecast_days": 3,
        },
        timeout=15,
    )
    response.raise_for_status()
    return response.json()


class WeatherTools(Star):
    def __init__(self, context: Context) -> None:
        super().__init__(context)
        self.settings = _load_settings()

    def _resolve_city(self, city: str | None) -> tuple[str, dict]:
        city = (city or "").strip()
        if not city:
            city = self.settings.get("active") or "新加坡"
        known = self.settings.get("cities", {}).get(city)
        if known:
            return city, known
        record = _geocode(city)
        return record["name"], record

    @filter.llm_tool(name="get_weather")
    async def get_weather(self, event: AstrMessageEvent, city: str = ""):
        """查一个城市的实时天气和未来三天降雨，用来提醒主人带伞、防晒或穿衣。

        主人没有指定城市时留空，使用当前常驻城市（默认新加坡）。
        如果主人说“上海”“新加坡”，可以直接传城市名。

        Args:
            city(string): 城市名，例如 新加坡、上海；不填用默认城市
        """
        try:
            name, record = await asyncio.to_thread(self._resolve_city, city)
            data = await asyncio.to_thread(
                _fetch_weather,
                float(record["latitude"]),
                float(record["longitude"]),
            )
            return _format_weather(name, data)
        except Exception as exc:
            logger.warning("[weather] get_weather failed: %s", exc)
            return f"天气查询失败了：{exc}"

    @filter.llm_tool(name="set_weather_city")
    async def set_weather_city(self, event: AstrMessageEvent, city: str):
        """切换常驻城市。主人说“我回上海了/我在上海/回新加坡了”时调用。

        Args:
            city(string): 新城市名，例如 上海、新加坡
        """
        city = (city or "").strip()
        if not city:
            return "城市名是空的，没改。"
        try:
            name, record = await asyncio.to_thread(self._resolve_city, city)
            self.settings.setdefault("cities", {})[name] = {
                "latitude": record["latitude"],
                "longitude": record["longitude"],
            }
            self.settings["active"] = name
            _save_settings(self.settings)
            return f"常驻城市已切换到 {name}，以后查天气默认用它。"
        except Exception as exc:
            logger.warning("[weather] set city failed: %s", exc)
            return f"切换城市失败：{exc}"

    @filter.on_llm_request(priority=1000)
    async def remind_city_switch(self, event: AstrMessageEvent, req):
        text = getattr(event, "message_str", "") or ""
        prompt = getattr(req, "system_prompt", "") or ""
        additions = []
        if re.search(r"(回|到|在)(上海|新加坡)", text):
            additions.append(
                "主人这句话说明他在上海或新加坡。回复前先调用 set_weather_city，"
                "把常驻城市切换过去，再自然回话。"
            )
        if re.search(r"(天气|气温|温度|下雨|降雨|带伞|冷不冷|热不热)", text):
            additions.append(
                "主人在问天气。先调用 get_weather（没指定城市就留空），"
                "再根据返回的温度和降雨概率自然回答；不要凭感觉编天气。"
            )
        if additions:
            req.system_prompt = prompt + "\n" + "\n".join(additions) + "\n不要提“工具”两个字。"
