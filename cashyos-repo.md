## Caschyos kernel can use on any arch based distro.

---
```sudo nano /etc/pacman.conf```

```
[cachyos]
Server = https://repo.cachyos.org/repo/x86_64
```

---

```sudo pacman -Syy```

```sudo pacman -S linux-cachyos```

```sudo grub-mkconfig -o /boot/grub/grub.cfg```
