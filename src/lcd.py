class LCD:
    def __init__(self, dev_path: str = '/dev/lcd'):
        self.dev_path = dev_path
        self.file = open(self.dev_path, 'r+')

    def __del__(self):
        self.file.close()

    def clear(self):
        self.file.seek(0)
        self.file.write(' ' * 32)
        self.file.flush()

    def write(self, text: str):
        self.file.seek(0)
        self.file.write(text[:32].ljust(32))
        self.file.flush()

    def read(self) -> str:
        self.file.seek(0)
        return self.file.read(32).rstrip()

    def __getitem__(self, line: int):
        if line in (0, 1):
            self.file.seek(line * 16)
            return self.file.read(16).rstrip()
        raise AttributeError(f"'LCD' only has two lines (0 and 1), not '{line}'")
    
    def __setitem__(self, line: int, text: str):
        if line in (0, 1):
            self.file.seek(line * 16)
            self.file.write(text[:16].ljust(16))
            self.file.flush()
        else:
            raise AttributeError(f"'LCD' only has two lines (0 and 1), not '{line}'")