class ConversationMemory:
    def __init__(self, max_size: int = 20):
        self.max_size = max_size
        self.messages = []
        
    def add_message(self, role: str, content: str):
        self.messages.append({"role": role, "content": content})
        if len(self.messages) > self.max_size:
            self.messages.pop(0)  # Drop oldest message
            
    def get_history(self) -> list:
        return self.messages.copy()
        
    def clear(self):
        self.messages = []
