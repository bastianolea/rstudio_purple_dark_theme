# AGENTS.md

Tema para RStudio. Los `.rstheme` **se generan**; la fuente está en `fuente/`.

## Regla principal

**Nunca editar un `.rstheme` directamente.** Se sobrescriben en cada build. Todo
cambio va a `fuente/<tema>/*.css` y después se corre `construir_tema()`.

Tampoco editar `fuente/dark/02-editor.css`, `03-ide.css` ni `04-terminal.css`:
son salida de `{rsthemes}` y se conservan intactas para poder regenerarlas. Los
overrides sobre esos bloques van en `05-estable.css`, marcados con `OVERRIDE`.

## Estructura

```
fuente/dark/01-cabecera.css   metadata (rs-theme-name, rs-theme-is-dark)
fuente/dark/02-editor.css     ace / sintaxis        (generado, no editar)
fuente/dark/03-ide.css        chrome básico         (generado, no editar)
fuente/dark/04-terminal.css   paleta xterm          (generado, no editar)
fuente/dark/05-estable.css    parches con clases estables de RStudio
fuente/dark/06-chrome.css     parches con {{nombres.semanticos}}
fuente/light/                 igual, con 02-base.css unificado

R/mapa-clases.R   ruta_rstudio, archivo_permutacion, mapa_clases, clase
R/construir.R     construir_tema, resolver_tokens, renombrar_tema, validar_css
R/doctor.R        doctor, buscar_clase, buscar_miembro, css_rstudio
```

`construir_tema()` concatena los `.css` en orden alfabético (el prefijo numérico
fija la cascada), resuelve los tokens y valida antes de escribir.

## El problema que resuelve este repo

RStudio se compila con GWT, que ofusca las clases CSS de su propia interfaz
(`GFRCULXJX`). El nombre cambia en cada release, así que los parches al chrome
del IDE —bordes de paneles, barra de estado, panel de entorno, diálogos,
outline— se rompían en cada actualización. No hay API para eso; el contrato
público de temas cubre solo `.ace_*`, `.xterm*`, `.rstudio-themes-*`,
`.rstheme_*`, `.gwt-*`, `#rstudio_*` y atributos ARIA / `data-slot`.

El mapa nombre semántico → clase ofuscada se extrae de la instalación de
RStudio cruzando dos archivos que Posit sí envía:

1. `www-symbolmaps/<hash>.symbolMap`, campos
   `simbolo,jsniIdent,claseJava,miembro,archivo,linea,fragmento`. Interesan las
   líneas con `ClientBundleGenerator` en la clase y `()Ljava/lang/String;` en el
   jsniIdent.
2. `www/rstudio/<mismo-hash>.cache.js`, donde ese símbolo aparece como
   `function xJf(){return OXv}` y la tabla de strings define `OXv='GFRCULXJX'`.

Solo una de las ~15 permutaciones `.cache.js` lleva el CSS; se identifica por
contener `rstheme_toolbarWrapper`. El prefijo de ofuscación es único por
compilación pero su largo varía (7 en `GFRCULX`, 8 en `GBQS1KEB` y `GNJ4OY0C`),
así que se detecta por frecuencia, no se asume.

En RStudio 2026.07.1 el mapa resuelve 1546 de 1661 clases.

## Trampa principal

**Los sufijos de las clases ofuscadas se desplazan entre versiones.** Nunca
asumir que `GNUEVO<sufijo>` es el mismo elemento que `GVIEJO<sufijo>`.
Contraejemplos verificados en este repo:

- `GNJ4OY0CFS` era `ThemeResources.header`; `GFRCULXFS` es
  `ThemeResources.gutterInfo`.
- El parche del botón de modo visual usaba la clase del toolbar en la posición
  del botón: los cuatro sufijos de la cadena se habían corrido una posición.

Antes de escribir una regla contra un nombre semántico, confirmarlo con
`css_rstudio("Recurso.miembro")`, que imprime el CSS propio de RStudio para esa
clase. Si las declaraciones no cuadran con el elemento, el nombre está mal.

`doctor()` sugiere candidatos del mismo sufijo, pero los marca explícitamente
como pista a confirmar, no como respuesta.

## Trampa: los `#rstudio_*` no son el elemento que se pinta

Los ids `#rstudio_*` son el selector más estable que hay, pero casi nunca están
sobre el elemento que tiene el borde o el fondo. Muchos widgets de RStudio son
un `Composite` cuyo `HTMLPanel` de GWT agrega un `<div>` contenedor propio: el
id (y las clases que el código Java agrega con `addStyleName`) caen en ese
contenedor invisible, y la caja visible es su hijo. Si se le pone fondo o borde
al elemento del id aparece un segundo cuadro alrededor del control.

Ejemplo verificado, el buscador "Go to file/function" de la barra de menú:

```html
<div id="rstudio_code_search_widget" class="{{CodeSearchResources.codeSearchWidget}}">
  <div class="search">                      <!-- la caja: borde y alto -->
    <div class="{{ThemeResources.left}}">    <!-- extremo de 6px, fondo propio -->
    <div class="rstheme_center">             <!-- el relleno, detrás del texto -->
    <div class="{{ThemeResources.right}}">   <!-- display:none dentro de .search -->
```

Dos señales para detectarlo sin abrir el inspector:

- Si `css_rstudio()` devuelve reglas propias de RStudio con combinador de
  descendencia (`.GFRCULXDTB .search {...}`), la clase del widget está en un
  ancestro, no en el elemento estilado.
- La plantilla UiBinder se puede reconstruir del `.cache.js`: la función que
  arma el HTML concatena trozos literales (`MBv="<div class='"`,
  `PBv="'> <div class='"`, ...) con los accesores de estilo. Buscar la función
  que recibe `styles.<algo>()` y resolver esos trozos da el DOM exacto.

Corolario para escribir reglas: apuntar el borde y el fondo a los hijos
(`#id .search`, `#id .search > div`) y dejar el elemento del id sin pintar. El
`#id` sirve para acotar el alcance —los buscadores del IDE comparten `.search`
y `.rstheme_center`— y además gana en especificidad (1-1-0) contra los
`!important` de los bloques generados (0-3-0), que solo usan clases.

## Convenciones

- Comentarios y nombres de funciones en español.
- En `05-estable.css` y `06-chrome.css`: un comentario por regla describiendo
  qué elemento arregla; lo más nuevo al final.
- Las reglas recuperadas de versiones anteriores se marcan `RECUPERADA:` con el
  motivo, para poder revisarlas a ojo y revertirlas.
- Las reglas desactivadas se dejan comentadas con su motivo, no se borran.
- Los temas generados llevan sufijo `-2` en el archivo y en `rs-theme-name`,
  para convivir con los `.rstheme` anteriores hechos a mano (que se conservan
  solo como referencia y están rotos en 2026.07+). Se cambia con
  `construir_tema(..., sufijo = "")`.

## Entorno

- RStudio está en `~/Applications/RStudio.app`, **no** en `/Applications`.
  `ruta_rstudio()` prueba varias rutas y el ancla `RSTUDIO_PANDOC`; se puede
  forzar con `options(basti.rstudio_path = ...)`.
- Dependencias: `stringr`, `rstudioapi`. `rsthemes` no está instalado y no hace
  falta.
- `mapa_clases()` y `js_rstudio()` cachean por sesión: parsear el `.cache.js`
  de 7 MB toma unos segundos.
- `construir_tema(instalar = TRUE)` necesita RStudio corriendo (usa
  `rstudioapi`); desde `Rscript` falla con "RStudio not running". Para
  verificar un cambio en la terminal, construir sin instalar.

## Pendientes conocidos

- `GFRCULXPAB` (ventana de "session aborted") va literal en `06-chrome.css`:
  es la única clase del tema que el mapa no sabe nombrar, y se va a romper en
  la próxima actualización. `doctor()` la reporta como "sin nombre".
- Los bordes de paneles y la barra de estado se unificaron en `#111111`,
  tomando la intención del último cambio hecho a mano. Antes solo algunas ramas
  del selector recibían ese valor y el resto quedaba en `rgb(22,22,22)`.
- Dos reglas quedaron desactivadas a propósito, documentadas en la fuente: el
  borde de los popups de menú (estaba escrita `border: #404040`, CSS inválido)
  y ocultar los separadores de la barra de herramientas (estaba dentro de un
  comentario sin cerrar).
- Sin implementar: resolución por huella de las declaraciones, para
  instalaciones sin `www-symbolmaps` (RStudio Server o instalaciones
  recortadas). Hoy `mapa_clases()` falla con un mensaje claro en ese caso.

## Verificación después de tocar la fuente

```r
source("R/mapa-clases.R"); source("R/construir.R"); source("R/doctor.R")
construir_tema("dark"); construir_tema("light")
doctor()   # debe dar OBSOLETAS: 0 y 0 tokens sin resolver en los temas -2
```

Para un cambio grande, comparar reglas contra el `.rstheme` anterior
normalizando espacios y comentarios: el diff debe contener solo lo intencional.
