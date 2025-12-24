# termux-space-whisper

Descarga un space de Twitter, extrae el audio y genera una **minuta por minuto** y lo guarda en txt para que lo puedas leer o hacer búsquedas

El script `manny-whisper.bash` hace:

1. Descargar el Space (y lo guarda)
2. Extraer el audio
3. Transcribir con `whisper-cli`
4. Generar un archivo TXT con la transcripción agrupada por minuto

---

## Requisitos

- Android
- Termux [Play Store](https://play.google.com/store/apps/details?id=com.termux&hl=en_US) o [página oficial](https://termux.dev/en/)
- Espacio suficiente en almacenamiento (Spaces pueden ser largos)

---

## Instalación

### 1. Instalar Termux

Instalar y abrir Termux.

---

### 2. Permitir acceso al almacenamiento

```bash
termux-setup-storage
```

### 3. Actualizar e instalar dependencias

```bash
pkg update -y && pkg upgrade -y
pkg install -y git cmake clang make ffmpeg python
```

### 4. Clonar whisper.cpp

```bash
cd ~
git clone https://github.com/ggerganov/whisper.cpp
cd whisper.cpp
```
### 5. Compilar

```bash
rm -rf build
cmake -S . -B build \
  -DGGML_NATIVE=OFF \
  -DGGML_CPU_ALL_VARIANTS=OFF \
  -DGGML_OPENMP=OFF \
  -DGGML_CPU_ARM_ARCH=OFF

cmake --build build -j"$(nproc)"
```

### 5.1. Verificar que exista el bin
```bash
ls ~/whisper.cpp/build/bin/whisper-cli
```

### 6. Descargar modelo Whisper
```bash
cd ~/whisper.cpp
bash ./models/download-ggml-model.sh base
```
NOTA. Si su telefono está muy culero en vez de "base" pongan "tiny"

### 7. Descargar yt-dlp
```bash
pip install -U yt-dlp
```

### 8. Preparar workspace
```bash
mkdir -p ~/storage/downloads/yt-dlp
```

### 9. Instalar el script

Bajarlo de github
```bash
cd ~
git clone https://github.com/TU_USUARIO/termux-space-whisper.git
```

Hacerlo global y dar permisos
```bash
cp termux-space-whisper/manny-whisper.bash $PREFIX/bin/manny-whisper
chmod 755 $PREFIX/bin/manny-whisper
```

### 9. Uso
Correr el whisper y reemplazarlo por la url del space (no del post)
```bash
manny-whisper "https://x.com/i/spaces/ID_DEL_SPACE"
```

Si tienes un buen teléfono puedes seleccionar el número de hilos (aquí uso 6 hilos como ejemplo)
```bash
manny-whisper "https://x.com/i/spaces/ID_DEL_SPACE" 6
```

### 9. Resultado
Los archivos se guardan en:
```bash
Download/yt-dlp/
```
Y te genera dos archivos, el audio y el texto
```bash
titulo_ID.m4a
```

```bash
titulo_ID_minuta_1min.txt
```
NOTA: El minutaje es cada minuto (vaya). Pero se puede modificar para que sea cada x minutos

### License
Termux Space Whisper's code are released under the MIT License. See LICENSE for further details.


