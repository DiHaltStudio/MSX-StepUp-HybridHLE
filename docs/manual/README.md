# Manuales de usuario

Las dos ediciones disponibles son:

- Español: `manual.tex` → `manual.pdf`
- English: `manual-en.tex` → `manual-en.pdf`

Para generar los PDF se necesita una
distribución LaTeX con `latexmk`, `pdflatex` y los paquetes habituales de
TeX Live.

En Debian o Ubuntu se pueden instalar las dependencias con:

```bash
sudo apt install latexmk texlive-latex-extra texlive-lang-spanish
```

Después, desde esta carpeta:

```bash
make
```

El comando genera ambos PDF. Para borrar los archivos temporales:

```bash
make clean
```

También se puede subir cualquiera de los archivos `.tex` a Overleaf junto con
`assets/graphics/intro.png` y `assets/graphics/stepup_logo.png`; en ese caso
hay que adaptar `\graphicspath` a la ubicación de las imágenes en el proyecto
de Overleaf.
