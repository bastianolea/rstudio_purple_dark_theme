# clases.R --------------------------------------------------------------
#
# Traduce los nombres semánticos de los elementos de la interfaz de RStudio
# a las clases CSS ofuscadas que usa la versión instalada.
#
# RStudio se compila con GWT, que renombra las clases CSS de sus componentes a
# nombres como "GFRCULXJX". Ese nombre cambia en cada versión de RStudio, y por
# eso los parches del tema que apuntan al chrome del IDE se rompen al
# actualizar. Pero RStudio *envía* la información para deshacer el renombre:
#
#   1. www-symbolmaps/<hash>.symbolMap  relaciona cada símbolo JS con el
#      miembro Java del que salió, incluidos los getters de CssResource:
#        xJf,...ThemeResources_..._InlineClientBundleGenerator$1::windowFrameObject()Ljava/lang/String;,...,windowFrameObject,...
#   2. www/rstudio/<hash>.cache.js  define ese símbolo como
#        function xJf(){return OXv}
#      y su tabla de strings define
#        OXv='GFRCULXJX'
#
# Encadenando ambos se obtiene el mapa completo. En RStudio 2026.07.1 resuelve
# ~1500 de las ~1660 clases ofuscadas del bundle.
#
# Uso:
#   source("R/clases.R")
#   m <- mapa_clases()
#   clase("ThemeResources.windowFrameObject")   # -> "GFRCULXJX"

library(stringr)


# Ubicación de RStudio -------------------------------------------------------

# Sube por el árbol de directorios buscando la carpeta del bundle web.
subir_hasta_app <- function(ruta, niveles = 8) {
  if (is.na(ruta) || !nzchar(ruta)) return(NULL)
  for (i in seq_len(niveles)) {
    if (es_app_rstudio(ruta)) return(ruta)
    padre <- dirname(ruta)
    if (identical(padre, ruta)) break
    ruta <- padre
  }
  NULL
}

es_app_rstudio <- function(ruta) {
  !is.null(ruta) && nzchar(ruta) && dir.exists(file.path(ruta, "www", "rstudio"))
}

#' Ruta a la carpeta `Resources/app` de la instalación de RStudio
#'
#' Prueba, en orden: el argumento, la opción `basti.rstudio_path`, el ancla
#' RSTUDIO_PANDOC (funciona al correr dentro de RStudio) y rutas por defecto
#' de macOS y Linux.
ruta_rstudio <- function(ruta = NULL) {
  candidatas <- c(
    ruta,
    getOption("basti.rstudio_path"),
    subir_hasta_app(Sys.getenv("RSTUDIO_PANDOC")),
    subir_hasta_app(Sys.getenv("QUARTO_PATH")),
    path.expand("~/Applications/RStudio.app/Contents/Resources/app"),
    "/Applications/RStudio.app/Contents/Resources/app",
    "/usr/lib/rstudio/resources/app",
    "/usr/lib/rstudio",
    "/usr/lib/rstudio-server"
  )
  candidatas <- candidatas[!is.na(candidatas) & nzchar(candidatas)]

  for (c in candidatas) if (es_app_rstudio(c)) return(normalizePath(c))

  stop(
    "No encontré la instalación de RStudio.\n",
    "Probé estas rutas:\n  ", paste(candidatas, collapse = "\n  "), "\n",
    "Indícala a mano con:\n",
    '  options(basti.rstudio_path = "/ruta/a/RStudio.app/Contents/Resources/app")',
    call. = FALSE
  )
}

#' Versión de RStudio de una instalación dada
version_rstudio <- function(app = ruta_rstudio()) {
  v <- file.path(app, "VERSION")
  if (file.exists(v)) str_trim(readLines(v, warn = FALSE)[1]) else NA_character_
}

#' Localiza la permutación de GWT que contiene el CSS compilado
#'
#' De los ~15 archivos .cache.js solo uno lleva el CSS de la interfaz. Se
#' identifica por contener la clase estable `rstheme_toolbarWrapper`, que
#' sobrevive entre versiones porque está marcada como externa en el CSS de
#' RStudio. Devuelve las rutas del .cache.js y del .symbolMap del mismo hash.
archivo_permutacion <- function(app = ruta_rstudio()) {
  js <- list.files(file.path(app, "www", "rstudio"),
                   pattern = "\\.cache\\.js$", full.names = TRUE)
  if (!length(js)) stop("No hay archivos .cache.js en ", app, call. = FALSE)

  # el que lleva el CSS es también el más grande; probar en ese orden acelera
  js <- js[order(file.size(js), decreasing = TRUE)]
  encontrado <- NULL
  for (f in js) {
    if (any(grepl("rstheme_toolbarWrapper", readLines(f, warn = FALSE), fixed = TRUE))) {
      encontrado <- f
      break
    }
  }
  if (is.null(encontrado)) {
    stop("Ningún .cache.js contiene el CSS de la interfaz (buscaba ",
         "'rstheme_toolbarWrapper'). ¿Cambió la estructura de RStudio?",
         call. = FALSE)
  }

  hash <- sub("\\.cache\\.js$", "", basename(encontrado))
  sm <- file.path(app, "www-symbolmaps", paste0(hash, ".symbolMap"))

  list(js = encontrado, symbolmap = if (file.exists(sm)) sm else NA_character_,
       hash = hash)
}


# Construcción del mapa ------------------------------------------------------

# Getters compilados: `function xJf(){return OXv}` o `function _Rd(){return 'GFRCULXBG'}`
# Devuelve un vector nombrado símbolo -> valor devuelto (ya resuelto).
getters_de_string <- function(js) {
  # Tabla de strings del compilador. El valor se restringe a caracteres de
  # identificador para no arrastrar los blobs de CSS, HTML y base64 del bundle.
  tabla <- str_match_all(js, "([A-Za-z0-9_$]{2,6})='([A-Za-z0-9_-]{2,40})'")[[1]]
  strings <- setNames(tabla[, 3], tabla[, 2])

  literales <- str_match_all(
    js, "function ([A-Za-z0-9_$]{2,8})\\(\\)\\{return '([A-Za-z0-9_-]{2,40})'\\}"
  )[[1]]

  indirectos <- str_match_all(
    js, "function ([A-Za-z0-9_$]{2,8})\\(\\)\\{return ([A-Za-z0-9_$]{2,6})\\}"
  )[[1]]

  c(
    setNames(literales[, 3], literales[, 2]),
    setNames(unname(strings[indirectos[, 3]]), indirectos[, 2])
  )
}

# Entradas del symbolMap que corresponden a getters de CssResource.
# Formato: símbolo, jsniIdent, claseJava, miembro, archivo, línea, fragmento
getters_de_css <- function(symbolmap) {
  lineas <- readLines(symbolmap, warn = FALSE)
  lineas <- lineas[grepl("ClientBundleGenerator", lineas, fixed = TRUE)]
  lineas <- lineas[grepl("()Ljava/lang/String;", lineas, fixed = TRUE)]

  campos <- str_split_fixed(lineas, ",", 5)
  simbolo <- campos[, 1]
  clase   <- campos[, 3]
  miembro <- campos[, 4]

  ok <- nzchar(simbolo) & nzchar(miembro)

  # org.rstudio.core.client.theme.res.ThemeResources_gecko1_8_false_en_Inline...
  #   -> "ThemeResources"  (se descarta el sufijo de permutación y locale)
  recurso <- sub("_.*$", "", sub("^.*\\.", "", clase[ok]))

  data.frame(simbolo = simbolo[ok], recurso = recurso, miembro = miembro[ok],
             stringsAsFactors = FALSE)
}

.cache_mapa <- new.env(parent = emptyenv())

#' Mapa nombre semántico -> clase CSS ofuscada
#'
#' Devuelve un data.frame con las columnas `recurso`, `miembro`, `token`
#' (= "recurso.miembro", lo que se escribe en la fuente del tema) y `clase`
#' (el nombre ofuscado de esta versión de RStudio).
#'
#' El resultado se guarda en caché por sesión: parsear el .cache.js de 7 MB
#' toma unos segundos.
mapa_clases <- function(app = ruta_rstudio(), recargar = FALSE) {
  perm <- archivo_permutacion(app)
  llave <- paste(perm$js, file.mtime(perm$js))
  if (!recargar && !is.null(.cache_mapa[[llave]])) return(.cache_mapa[[llave]])

  if (is.na(perm$symbolmap)) {
    stop("Falta ", file.path(app, "www-symbolmaps"), ".\n",
         "Esta instalación de RStudio no incluye los symbol maps, así que no ",
         "se puede reconstruir el mapa de clases.", call. = FALSE)
  }

  js <- paste(readLines(perm$js, warn = FALSE), collapse = "\n")
  valores <- getters_de_string(js)
  css <- getters_de_css(perm$symbolmap)

  css$clase <- unname(valores[css$simbolo])
  css <- css[!is.na(css$clase), ]

  # Quedarse solo con las clases del prefijo de ofuscación de este build: los
  # getters de CssResource también devuelven valores que no son clases (@def,
  # rutas de imágenes, etc.) y hay que descartarlos.
  pref <- detectar_prefijo(css$clase)
  css <- css[startsWith(css$clase, pref), ]

  css$token <- paste(css$recurso, css$miembro, sep = ".")
  m <- unique(css[, c("recurso", "miembro", "token", "clase")])

  # Cada miembro aparece una vez por permutación (gecko1_8/safari x en/fr x
  # useNativeDialogs) y todas dan la misma clase, así que el duplicado se
  # descarta. Si aun así un token resuelve a dos clases distintas es porque el
  # recurso está declarado más de una vez en el bundle; se anota y `clase()`
  # avisa solo si alguien pide ese token en concreto.
  ambiguos <- unique(m$token[duplicated(m$token)])
  m <- m[!duplicated(m$token), ]

  m <- m[order(m$recurso, m$miembro), ]
  rownames(m) <- NULL
  attr(m, "prefijo") <- pref
  attr(m, "version") <- version_rstudio(app)
  attr(m, "app") <- app
  attr(m, "ambiguos") <- ambiguos

  .cache_mapa[[llave]] <- m
  m
}

# Detecta el prefijo de ofuscación de GWT en un vector de valores.
#
# GWT usa un único prefijo por compilación (verificado en 2026.07.1: las 1661
# clases del bundle comparten "GFRCULX"), pero su largo varía entre versiones
# ("GNJ4OY0C" y "GBQS1KEB" tienen 8 caracteres). Se detecta por frecuencia: el
# prefijo verdadero lo comparten todas las clases, así que su recuento se
# mantiene alto mientras se alarga y cae de golpe al pasarse de largo.
detectar_prefijo <- function(valores, minimo = 50L) {
  candidatos <- valores[grepl("^[A-Z][A-Z0-9]{5,}$", valores)]
  if (length(candidatos) < minimo) {
    stop("Solo encontré ", length(candidatos), " valores con forma de clase ",
         "ofuscada; esperaba al menos ", minimo, ". ¿Cambió el esquema de ",
         "compilación de RStudio?", call. = FALSE)
  }

  mejor <- lapply(4:12, function(k) {
    t <- sort(table(substr(candidatos, 1, k)), decreasing = TRUE)
    list(largo = k, prefijo = names(t)[1], n = as.integer(t[1]))
  })
  n <- vapply(mejor, `[[`, integer(1), "n")
  if (max(n) < minimo) {
    stop("Ningún prefijo es compartido por al menos ", minimo, " clases. ",
         "¿Cambió el esquema de compilación de RStudio?", call. = FALSE)
  }

  # el prefijo completo es el más largo que sigue cubriendo casi todas las clases
  aceptables <- which(n >= 0.95 * n[1])
  mejor[[max(aceptables)]]$prefijo
}

#' Clase ofuscada de uno o más tokens semánticos
#'
#' Devuelve NA para los que no resuelven, para que quien llama decida qué hacer.
clase <- function(token, mapa = mapa_clases()) {
  dudosos <- intersect(token, attr(mapa, "ambiguos"))
  if (length(dudosos)) {
    warning("Estos nombres están declarados más de una vez en el bundle de ",
            "RStudio y podrían resolver a la clase equivocada: ",
            paste(dudosos, collapse = ", "), call. = FALSE)
  }
  unname(setNames(mapa$clase, mapa$token)[token])
}

#' Prefijo de ofuscación de la versión instalada (p. ej. "GFRCULX")
prefijo_gwt <- function(app = ruta_rstudio()) attr(mapa_clases(app), "prefijo")
