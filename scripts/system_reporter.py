def get_ram():
    with open("/proc/meminfo") as f:
        contenu = f.read()
        MemTotal = int(contenu.split()[1])
        resultat = MemTotal / 1024
        resultat = round(resultat, 2)
        return resultat


def get_cpu():
    with open("/proc/cpuinfo") as f:
        contenu = f.read()
        nb_cpu = contenu.count("model name")
        return nb_cpu


def get_disk():
    import os
    stats = os.statvfs("/")
    total_gb = (stats.f_blocks * stats.f_frsize) / (1024 ** 3)
    return round(total_gb, 2)


def main():
    print(f"RAM   : {get_ram()} MB")
    print(f"CPU   : {get_cpu()} cœurs")
    print(f"Disque: {get_disk()} GB")


main()
