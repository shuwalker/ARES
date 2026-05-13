"""Engineering models — structured data for hardware, propulsion, and test specs.

TACFI thruster parameters, catalyst specs, test results, material properties.
Everything that goes into an engineering decision or a PDR document gets a
Pydantic model here. These models serve as the contract between:
  - MCP skill servers (tool parameter validation)
  - The ARES memory system (structured recall)
  - The app UI (SwiftUI renders these types directly from JSON)
  - NAS files (read/write validated data)
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, field_validator


# ---------------------------------------------------------------------------
# Thruster specifications (TACFI, JP01, etc.)
# ---------------------------------------------------------------------------

class ThrusterType(str, Enum):
    cold_gas = "cold_gas"
    monopropellant = "monopropellant"
    bipropellant = "bipropellant"
    hybrid = "hybrid"
    electric = "electric"
    solid = "solid"


class ThrusterSpec(BaseModel):
    """Complete specification for a thruster system."""

    id: str = Field(..., description="Unique identifier, e.g. 'tacfi-rft-1'")
    name: str = Field(..., description="Human-readable name, e.g. 'TACFI RFT Unit 1'")
    thruster_type: ThrusterType = ThrusterType.monopropellant
    project: str = Field("tacfi", description="Parent project ID")

    # Performance
    thrust_mN: float = Field(..., description="Thrust in millinewtons")
    mass_flow_rate_mg_s: float = Field(..., description="Mass flow rate in mg/s")
    specific_impulse_s: float = Field(..., description="Specific impulse in seconds")
    response_time_ms: Optional[float] = Field(None, description="Response time in milliseconds")

    # Physical
    dry_mass_g: float = Field(..., description="Dry mass in grams")
    propellant_mass_g: float = Field(..., description="Propellant mass in grams")
    dimensions_mm: Optional[dict] = Field(None, description="Dimensions L×W×H in mm")

    # Operating conditions
    inlet_pressure_bar: Optional[float] = Field(None, description="Inlet pressure in bar")
    operating_temp_range_C: Optional[tuple[float, float]] = Field(None, description="(min, max) in Celsius")

    # Documentation
    source: str = Field("", description="Where this data came from (PDR, test, datasheet)")
    notes: str = Field("")
    updated_at: datetime = Field(default_factory=datetime.now)


# ---------------------------------------------------------------------------
# Catalyst parameters
# ---------------------------------------------------------------------------

class CatalystType(str, Enum):
    silver = "silver"
    iridium = "iridium"
    platinum = "platinum"
    shell_405 = "shell_405"
    custom = "custom"


class CatalystParams(BaseModel):
    """Catalyst bed specification for monopropellant thrusters."""

    id: str = Field(..., description="Unique catalyst identifier")
    name: str = Field(...)
    catalyst_type: CatalystType = CatalystType.silver
    project: str = Field("tacfi")

    # Bed geometry
    bed_diameter_mm: float = Field(..., description="Catalyst bed diameter")
    bed_length_mm: float = Field(..., description="Catalyst bed length")
    screen_count: int = Field(..., description="Number of catalyst screens")
    mesh_size: Optional[int] = Field(None, description="Mesh size if applicable")

    # Performance
    decomposition_efficiency_pct: Optional[float] = Field(None, description="Decomposition efficiency %")
    pressure_drop_bar: Optional[float] = Field(None, description="Pressure drop across bed")
    startup_time_ms: Optional[float] = Field(None, description="Cold start time to steady state")

    # Material
    substrate_material: str = Field("", description="Screen substrate material")
    loading_mg: Optional[float] = Field(None, description="Catalyst loading in mg")
    firing_count: int = Field(0, description="Number of firings recorded")

    source: str = Field("")
    notes: str = Field("")
    updated_at: datetime = Field(default_factory=datetime.now)


# ---------------------------------------------------------------------------
# Test results
# ---------------------------------------------------------------------------

class TestType(str, Enum):
    hot_fire = "hot_fire"
    cold_flow = "cold_flow"
    pressure = "pressure"
    thermal = "thermal"
    vibration = "vibration"
    leak = "leak"
    endurance = "endurance"


class TestResult(BaseModel):
    """A single test result — hot fire, cold flow, pressure, etc."""

    id: str = Field(..., description="Test result ID")
    test_type: TestType = TestType.hot_fire
    project: str = Field("tacfi")

    # What was tested
    component_id: str = Field(..., description="ID of the thruster or catalyst tested")
    component_type: str = Field("thruster", description="thruster | catalyst | system")

    # When and where
    date: datetime = Field(default_factory=datetime.now)
    location: str = Field("", description="Test facility or 'bench'")

    # Results
    thrust_mN: Optional[float] = None
    mass_flow_rate_mg_s: Optional[float] = None
    chamber_pressure_bar: Optional[float] = None
    specific_impulse_s: Optional[float] = None
    response_time_ms: Optional[float] = None
    duration_s: Optional[float] = None
    success: bool = Field(True, description="Did the test pass?")

    # Data
    data_file_path: Optional[str] = Field(None, description="Path to raw data on NAS")
    video_path: Optional[str] = Field(None, description="Path to test video on NAS")

    notes: str = Field("")
    updated_at: datetime = Field(default_factory=datetime.now)


# ---------------------------------------------------------------------------
# Generic component & material specs
# ---------------------------------------------------------------------------

class ComponentSpec(BaseModel):
    """A mechanical or electrical component in a project."""
    id: str
    name: str
    project: str
    category: str = Field("", description="valve | tank | injector | electronics | feed | structural")
    manufacturer: str = ""
    part_number: str = ""
    mass_g: Optional[float] = None
    material: Optional[str] = None
    source: str = ""
    notes: str = ""
    updated_at: datetime = Field(default_factory=datetime.now)


class MaterialSpec(BaseModel):
    """A material used in project hardware."""
    id: str
    name: str
    material_type: str = Field("", description="metal | polymer | ceramic | composite | catalyst | propellant")
    project: str = ""
    properties: dict = Field(default_factory=dict, description="Key-value material properties")
    source: str = ""
    notes: str = ""
    updated_at: datetime = Field(default_factory=datetime.now)