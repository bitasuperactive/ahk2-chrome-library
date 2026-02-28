<div align="center">
  <h1>CHROME LIBRARY</h1>
</div>

[![Documentation](https://img.shields.io/badge/Documentación-HTML-blue?style=for-the-badge)](https://bitasuperactive.github.io/ahk2-chrome-library/)

**Chrome Library** es una implementación de la librería [ahk2_lib/Chrome](https://github.com/thqby/ahk2_lib/blob/master/Chrome.ahk) desarrollada por [thqby](https://github.com/thqby/). 
Proporciona una implementación ligera de automatización de Google Chrome utilizando el <a href="https://chromedevtools.github.io/devtools-protocol/" target="_blank">⇱Chrome DevTools Protocol (CDP)</a> 
mediante WebSocket en <a href="https://www.autohotkey.com/v2/" target="_blank">⇱AutoHotkey V2</a>.
El objetivo es ofrecer una alternativa minimalista a herramientas como Selenium o Puppeteer, permitiendo:
- Control directo del navegador
- Ejecución de JavaScript
- Navegación avanzada
- Automatización de formularios
- Gestión de pestañas

El proyecto se compone de tres clases principales:

<h3>1️⃣ ChromeV2</h3>

Responsable de la gestión del navegador a nivel HTTP (/json endpoint).

<h3>2️⃣ ChromeV2.Page</h3>

Encapsula la conexión WebSocket al Chrome DevTools Protocol.

<h3>3️⃣ JSWrapper</h3>

Simplifica la automatización mediante métodos de alto nivel que encapsulan JavaScript común.

## Ejemplo básico

Vamos a crear un automatismo que inicie sesión en una página web de prueba.

Inicializamos nuestra instancia de Chrome Debug. 
Yo guardaré los datos de la aplicación en el directorio "C:\Temp\ChromeDebug", el resto de los parámetros los podemos dejar por defecto, como el puerto de escucha 9222.
> [!TIP]
> La primera vez que ejecutemos el debugger de Chrome, nos pedirá configurar el navegador.

```
chromeManager := ChromeV2(,, ProfilePath := "C:\Temp\ChromeDebug")
```

Instanciamos el envoltorio de JavaScript que nos permitirá abrir, conectar e interactuar con la página.
```
loginPage := JSWrapper(chromeManager, "https://the-internet.herokuapp.com/login")
```

Para mostrar la administración de pestañas, vamos a cerrar la pestaña en blanco que nos abre Chrome.

```
blankPages := chromeManager.FindPages({url: "chrome://newtab/"}, matchMode := "exact")
chromeManager.ClosePage(blankPages[1], "exact")
```

Ejecutamos la función predefinida para el inicio de sesión indicando los selectores CSS para el input del usuario y contraseña, y para el mensaje de error en caso de que lo hubiera.
> [!TIP]
> Para encontrar el selector de un elemento en HTML como un botón, hacemos clic derecho en él, inspeccionar, clic derecho sobre la línea HTML del elemento y "copiar selector".

```
result := loginPage.Login(selectorUserInput := "#username"
    , selectorPasswordInput := "#password"
    , selectorLoginButton := "button[type='submit']"
    , selectorErrorOutput := "#flash.error"
    , userName := "tomsmith"
    , password := "SuperSecretPassword!"
)
if (result)
    MsgBox("Login exitoso.")
else
    MsgBox("Error de autenticación.")
```

Y por supuesto, podemos ejecutar instrucciones JS directamente.

```
loginPage.WaitForEvaluate('document.querySelector("#content > div > a > i").click()') ; hace clic en logout
```

#### ¡Pruébalo en tu script!

Así de fácil es automatizar la mayoría de páginas web. 
La clase JSWrapper te facilita las funciones esenciales para las interacciones HTML que necesitarás.
Siéntete libre de modificarla a conveniencia, pero antes échale un vistazo a la [documentación de clases](https://bitasuperactive.github.io/ahk2-chrome-library/annotated.html).
