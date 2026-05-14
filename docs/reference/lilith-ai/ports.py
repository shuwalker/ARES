from dataclasses import dataclass

@dataclass
class PortMap:
    AUDIO_RAW: int    = 5570   # Mic audio chunks -> Whisper STT
    STT_TEXT: int     = 5571   # Whisper text -> LLM Brain
    LLM_RESPONSE: int = 5572   # LLM output -> all consumers (PUB/SUB)
    TTS_CONTROL: int  = 5573   # TTS commands
    ROBOT_CMD: int    = 5574   # Robot motor/behavior commands (future use)
    PIPELINE_LOG: int = 5575   # Internal logging bus

def get_address(port: int, host: str = "127.0.0.1") -> str:
    """Returns a tcp connection string for the specified port."""
    return f"tcp://{host}:{port}"
