class NotFoundException(Exception):
    def __init__(self, message):
        super().__init__(message)
        self.message = message

class AdopterAlreadyExists(Exception):
    def __init__(self, message):
        super().__init__(message)
        self.message = message

class AnimalCantBeAdopted(Exception):
    def __init__(self, message):
        super().__init__(message)
        self.message = message