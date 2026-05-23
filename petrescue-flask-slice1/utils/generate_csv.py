import uuid
import os


def create_massive_file():
    filepath = "../large_microchips.csv"
    print(f"Generam fisierul {filepath} (1 milion de randuri)... Asteapta...")

    with open(filepath, "w") as f:
        for i in range(1_000_000):
            if i == 850_000:
                f.write("FIND_ME_SPECIAL_CHIP_999\n")
            else:
                f.write(f"{uuid.uuid4()}\n")

    print(f"Fisier generat cu succes! Dimensiune: {os.path.getsize(filepath) / (1024 * 1024):.2f} MB")


if __name__ == "__main__":
    create_massive_file()