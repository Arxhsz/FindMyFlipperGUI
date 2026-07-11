"""
Pydantic v2 models for FindMyFlipper gateway.
"""

from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class FindMyKeyModel(BaseModel):
    """Parsed representation of a .keys file."""

    private_key_base64: str
    private_key_hex: Optional[str] = None
    advertisement_key_base64: Optional[str] = None
    advertisement_key_hex: Optional[str] = None
    hashed_adv_key_base64: str
    generated_findmy_mac: str   # from the MAC field
    payload: str
    source_file_name: Optional[str] = None


class LocationReportModel(BaseModel):
    """A single decrypted Find My location report."""

    model_config = ConfigDict(populate_by_name=True)

    id: str
    timestamp: float
    iso_date_time: str = Field(alias="isoDateTime")
    lat: float
    lon: float
    confidence: int
    status: int
    source: str = "Find My Network"
