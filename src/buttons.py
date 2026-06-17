class Buttons:
    def __init__(self, dev_path: str = '/dev/buttons'):
        self.dev_path = dev_path
        self.file = open(self.dev_path, 'r')

    def __del__(self):
        self.file.close()

    @property
    def up(self) -> bool:
        self.file.seek(5)
        return self.file.read(1) == '1'
    
    @property
    def down(self) -> bool:
        self.file.seek(6)
        return self.file.read(1) == '1'
    
    @property
    def left(self) -> bool:
        self.file.seek(7)
        return self.file.read(1) == '1'
    
    @property
    def right(self) -> bool:
        self.file.seek(4)
        return self.file.read(1) == '1'
    
    @property
    def select(self) -> bool:
        self.file.seek(8)
        return self.file.read(1) == '1'
    
    @property
    def btn0(self) -> bool:
        self.file.seek(0)
        return self.file.read(1) == '1'
    
    @property
    def btn1(self) -> bool:
        self.file.seek(1)
        return self.file.read(1) == '1'
    
    @property
    def btn2(self) -> bool:
        self.file.seek(2)
        return self.file.read(1) == '1'
    
    @property
    def btn3(self) -> bool:
        self.file.seek(3)
        return self.file.read(1) == '1'
    
