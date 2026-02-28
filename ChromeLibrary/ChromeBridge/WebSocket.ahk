#Requires AutoHotkey v2.0
#DllLoad winhttp.dll

/************************************************************************
 * Cliente WebSocket (WinHTTP API) compatible con AutoHotKey v2.
 * Administra la conexión, eventos, envío y recepción de datos binarios 
 * y texto UTF-8, memoria y traducción de errores del sistema.
 * La comunicación puede ser tanto síncrona como asíncrona.
 * 
 * Ejemplo de uso:
 * ```
 * ws := WebSocket(wss_or_ws_url, {
 *	message: (self, data) => FileAppend(Data '`n', '*', 'utf-8'),
 *	close: (self, status, reason) => FileAppend(status ' ' reason '`n', '*', 'utf-8')
 * })
 * ws.sendText('hello'), Sleep(100)
 * ws.send(0, Buffer(10), 10), Sleep(100)
 * ```
 * 
 * @author thqby
 * @author ChatGPT (documentation)
 * @date 04/02/2026
 * @version 1.0.7
 * @Warning Dependencias:
 * - winhttp.dll
 * @see https://websocket.org/reference/websocket-api
 * @see https://github.com/thqby/ahk2_lib/blob/master/WebSocket.ahk
 * @see https://github.com/bitasuperactive/ahk2-chrome-library/blob/master/ChromeLibrary/ChromeBridge/WebSocket.ahk
 ***********************************************************************/
class WebSocket 
{
	/**
	 * @public
	 * {Integer}
	 * Identificador interno del WebSocket (`HINTERNET`).
	 */
	Ptr := 0 ;

	/**
	 * @public
	 * {Boolean} 
	 * Modo de funcionamiento: `true` modo asíncrono, `false` modo síncrono.
	 */
	async := 0 ;
	
	/**
	 * @public
	 * {Integer}
	 * Estado de la conexión WebSocket.
	 * - `0` → CONNECTING: La conexión se está estableciendo.
	 * - `1` → OPEN: La conexión está abierta y operativa.
	 * - `2` → CLOSING: Se está cerrando la conexión.
	 * - `3` → CLOSED: La conexión está cerrada o ha fallado.
	 */
	readyState := 0 ;

	/**
	 * @public
	 * {String}
	 * URL original del servidor WebSocket proporcionada al crear la instancia.
	 */
	url := '' ;

	/**
	 * @public
	 * {Array} 
	 * Lista interna de todos los handles WinHTTP creados durante el ciclo de vida del objeto 
	 * (`hSession`, `hConnect`, `hRequest`, `hWebSocket`).
	 * Se utiliza para garantizar una liberación correcta de recursos.
	 */
	HINTERNETs := [] ;

	/**
	 * @public
	 * Evento desencadenado cuando la conexión WebSocket se ha establecido correctamente.
	 */
	onOpen() => 0 ;

	/**
	 * @public
	 * Evento desencadenado cuando la conexión se cierra.
	 * @param {Integer} status Código de cierre WebSocket.
	 * @param {String} reason Motivo del cierre.
	 */
	onClose(status, reason) => 0 ;

	/**
	 * @public
	 * Evento desencadenado al recibir un mensaje binario.
	 * @param {Integer} data Puntero a los datos.
	 * @param {Integer} size Tamaño en bytes.
	 */
	onData(data, size) => 0 ;

	/**
	 * @public
	 * Evento desencadenado al recibir un mensaje de texto UTF-8.
	 * @param {String} msg Cadena recibida.
	 */
	onMessage(msg) => 0 ;

	/**
	 * @public
	 * Vuelve a establecer la conexión con el WebSocket utilizando los mismos parámetros originales.
	 */
	reconnect() => 0 ;

	/**
     * @public
     * Establece la conexión con el cliente WebSocket.
	 * @param {String} Url Dirección del servidor WebSocket (`ws://` o `wss://`).
	 * @param {Object} Events (Opcional) Un objeto de
	 * `{ open:(this)=>void, data:(this, data, size)=>bool, message:(this, msg)=>bool, close:(this, status, reason)=>void }`
	 * @param {Boolean} Async (Opcional) Si utilizar el modo asíncrono. Por defecto: `true`.
	 * @param {Object|Map|String} Headers (Opcional) Cabeceras adicionales para las conexiones.
	 * @param {Integer} TimeOut (Opcional) Tiempo máximo para las comunicaciones con el servidor: `resolve`, 
	 * `connect`, `send` y `receive`.
	 * @param {Integer} InitialSize (Opcional) Tamaño inicial del buffer de recepción. Por defecto: 8192 bytes.
	 */
	__New(Url, Events := 0, Async := true, Headers := '', TimeOut := 0, InitialSize := 8192) 
	{
		static contexts := Map()
		if (!RegExMatch(Url, 'i)^((?<SCHEME>wss?)://)?((?<USERNAME>[^:]+):(?<PASSWORD>.+)@)?(?<HOST>[^/:\s]+)(:(?<PORT>\d+))?(?<PATH>/\S*)?$', &m))
			Throw WebSocket.Error('Invalid websocket url')
		if !hSession := DllCall('Winhttp\WinHttpOpen', 'ptr', 0, 'uint', 0, 'ptr', 0, 'ptr', 0, 'uint', Async ? 0x10000000 : 0, 'ptr')
			Throw WebSocket.Error()
		this.async := Async := !!Async, this.url := Url
		this.HINTERNETs.Push(hSession)
		port := m.PORT ? Integer(m.PORT) : m.SCHEME = 'ws' ? 80 : 443
		dwFlags := m.SCHEME = 'wss' ? 0x800000 : 0
		if TimeOut
			DllCall('Winhttp\WinHttpSetTimeouts', 'ptr', hSession, 'int', TimeOut, 'int', TimeOut, 'int', TimeOut, 'int', TimeOut, 'int')
		if !hConnect := DllCall('Winhttp\WinHttpConnect', 'ptr', hSession, 'wstr', m.HOST, 'ushort', port, 'uint', 0, 'ptr')
			Throw WebSocket.Error()
		this.HINTERNETs.Push(hConnect)
		switch Type(Headers) {
			case 'Object', 'Map':
				s := ''
				for k, v in Headers is Map ? Headers : Headers.OwnProps()
					s .= '`r`n' k ': ' v
				Headers := LTrim(s, '`r`n')
			case 'String':
			default:
				Headers := ''
		}
		if (Events) {
			for k, v in Events.OwnProps()
				if (k ~= 'i)^(open|data|message|close)$')
					this.DefineProp('on' k, { call: v })
		}
		if (Async) {
			this.DefineProp('shutdown', { call: async_shutdown })
				.DefineProp('receive', { call: receive })
				.DefineProp('_send', { call: async_send })
		} else this.__cache_size := InitialSize
		connect(this), this.DefineProp('reconnect', { call: connect })

		connect(self) {
			if !self.HINTERNETs.Length
				Throw WebSocket.Error('The connection is closed')
			self.shutdown()
			if !hRequest := DllCall('Winhttp\WinHttpOpenRequest', 'ptr', hConnect, 'wstr', 'GET', 'wstr', m.PATH, 'ptr', 0, 'ptr', 0, 'ptr', 0, 'uint', dwFlags, 'ptr')
				Throw WebSocket.Error()
			self.HINTERNETs.Push(hRequest), self.onOpen()
			if (Headers)
				DllCall('Winhttp\WinHttpAddRequestHeaders', 'ptr', hRequest, 'wstr', Headers, 'uint', -1, 'uint', 0x20000000, 'int')
			if (!DllCall('Winhttp\WinHttpSetOption', 'ptr', hRequest, 'uint', 114, 'ptr', 0, 'uint', 0, 'int')
				|| !DllCall('Winhttp\WinHttpSendRequest', 'ptr', hRequest, 'ptr', 0, 'uint', 0, 'ptr', 0, 'uint', 0, 'uint', 0, 'uptr', 0, 'int')
				|| !DllCall('Winhttp\WinHttpReceiveResponse', 'ptr', hRequest, 'ptr', 0)
				|| !DllCall('Winhttp\WinHttpQueryHeaders', 'ptr', hRequest, 'uint', 19, 'ptr', 0, 'wstr', status := '00000', 'uint*', 10, 'ptr', 0, 'int')
				|| status != '101')
				Throw IsSet(status) ? WebSocket.Error('Invalid status: ' status) : WebSocket.Error()
			if !self.Ptr := DllCall('Winhttp\WinHttpWebSocketCompleteUpgrade', 'ptr', hRequest, 'ptr', 0)
				Throw WebSocket.Error()
			DllCall('Winhttp\WinHttpCloseHandle', 'ptr', self.HINTERNETs.Pop())
			self.HINTERNETs.Push(self.Ptr), self.readyState := 1
			(Async && async_receive(self))
		}

		async_receive(self) {
			static on_read_complete := get_sync_callback(), hHeap := DllCall('GetProcessHeap', 'ptr')
			static msg_gui := Gui(), wm_ahkmsg := DllCall('RegisterWindowMessage', 'str', 'AHK_WEBSOCKET_STATUSCHANGE', 'uint')
			static pHeapReAlloc := DllCall('GetProcAddress', 'ptr', DllCall('GetModuleHandle', 'str', 'kernel32', 'ptr'), 'astr', 'HeapReAlloc', 'ptr')
			static pSendMessageW := DllCall('GetProcAddress', 'ptr', DllCall('GetModuleHandle', 'str', 'user32', 'ptr'), 'astr', 'SendMessageW', 'ptr')
			static pWinHttpWebSocketReceive := DllCall('GetProcAddress', 'ptr', DllCall('GetModuleHandle', 'str', 'winhttp', 'ptr'), 'astr', 'WinHttpWebSocketReceive', 'ptr')
			static _ := (OnMessage(wm_ahkmsg, WEBSOCKET_READ_WRITE_COMPLETE, 0xff), DllCall('SetParent', 'ptr', msg_gui.Hwnd, 'ptr', -3))
			; #DllLoad E:\projects\test\test\x64\Debug\test.dll
			; on_read_complete := DllCall('GetProcAddress', 'ptr', DllCall('GetModuleHandle', 'str', 'test', 'ptr'), 'astr', 'WINHTTP_STATUS_READ_COMPLETE', 'ptr')
			NumPut('ptr', pws := ObjPtr(self), 'ptr', msg_gui.Hwnd, 'uint', wm_ahkmsg, 'uint', InitialSize, 'ptr', hHeap,
				'ptr', cache := DllCall('HeapAlloc', 'ptr', hHeap, 'uint', 0, 'uptr', InitialSize, 'ptr'), 'uptr', 0, 'uptr', InitialSize,
				'ptr', pHeapReAlloc, 'ptr', pSendMessageW, 'ptr', pWinHttpWebSocketReceive,
				contexts[pws] := context := Buffer(11 * A_PtrSize)), self.__send_queue := []
			context.DefineProp('__Delete', { call: self => DllCall('HeapFree', 'ptr', hHeap, 'uint', 0, 'ptr', NumGet(self, 3 * A_PtrSize + 8, 'ptr')) })
			DllCall('Winhttp\WinHttpSetOption', 'ptr', self, 'uint', 45, 'ptr*', context.Ptr, 'uint', A_PtrSize)
			DllCall('Winhttp\WinHttpSetStatusCallback', 'ptr', self, 'ptr', on_read_complete, 'uint', 0x80000, 'uptr', 0, 'ptr')
			if err := DllCall('Winhttp\WinHttpWebSocketReceive', 'ptr', self, 'ptr', cache, 'uint', InitialSize, 'uint*', 0, 'uint*', 0)
				self.onError(err)
		}

		static WEBSOCKET_READ_WRITE_COMPLETE(wp, lp, msg, hwnd) {
			static map_has := Map.Prototype.Has
			if !map_has(contexts, ws := NumGet(wp, 'ptr')) || (ws := ObjFromPtrAddRef(ws)).readyState != 1
				return
			switch lp {
				case 5:		; WRITE_COMPLETE
					try ws.__send_queue.Pop()
				case 4:		; WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE
					if err := NumGet(wp, A_PtrSize, 'uint')
						return ws.onError(err)
					rea := ws.QueryCloseStatus(), ws.shutdown()
					return ws.onClose(rea.status, rea.reason)
				default:	; WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE, WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE
					data := NumGet(wp, A_PtrSize, 'ptr')
					size := NumGet(wp, 2 * A_PtrSize, 'uptr')
					if lp == 2
						return ws.onMessage(StrGet(data, size, 'utf-8'))
					else return ws.onData(data, size)
			}
		}

		static async_send(self, type, buf, size) {
			if (self.readyState != 1)
				Throw WebSocket.Error('websocket is disconnected')
			(q := self.__send_queue).InsertAt(1, buf)
			while (err := DllCall('Winhttp\WinHttpWebSocketSend', 'ptr', self, 'uint', type, 'ptr', buf, 'uint', size, 'uint')) = 4317 && A_Index < 60
				Sleep(15)
			if err
				q.RemoveAt(1), self.onError(err)
		}

		static async_shutdown(self) {
			if self.Ptr
				DllCall('Winhttp\WinHttpSetOption', 'ptr', self, 'uint', 45, 'ptr*', 0, 'uint', A_PtrSize)
			(WebSocket.Prototype.shutdown)(self)
			try contexts.Delete(ObjPtr(self))
		}

		static get_sync_callback() {
			mcodes := ['g+wMVot0JBiF9g+E0QAAAItEJBw9AAAQAHUVi0YkagVW/3YI/3YE/9Beg8QMwhQAPQAACAAPhaYAAACLBolEJASLRCQgU1VXi1AEx0QkFAAAAADHRCQYAAAAAIP6BHRsi04Yi+qLAI0MAYlOGIPlAXV2i0YUiUQkFI1EJBBSUP92CItGJP92BIlMJCjHRhgAAAAA/9CNfhyFwHQHi14MOx91UYsHK0YYagBqAFCLRhQDRhhQ/3QkMItGKP/QhcB0HT3dEAAAdBaJRCQUagSNRCQUUP92CItGJP92BP/QX11bXoPEDMIUAIteHI1+HDvLcrED24tGIFP/dhRqAP92EP/QhcB0B4lGFIkf65aF7XSSx0QkFA4AB4DrsQ==',
				'SIXSD4QvAQAASIlcJCBBVkiD7FBIi9pMi/FBgfgAABAAdR9Ii0sITIvCi1IQQbkFAAAA/1NASItcJHhIg8RQQV7DQYH4AAAIAA+F3gAAAEiLAkljUQRIiWwkYEiJRCQwM8BIiXQkaEiJfCRwSMdEJDgAAAAASIlEJECD+gQPhIYAAABFiwGL6kiLQyhNjQQATIlDKIPlAQ+FnAAAAEiLQyBMi8qLUxBIi0sITIlEJEBMjUQkMEiJRCQ4SMdDKAAAAAD/U0BIjXswSIXAdAiLcxRIOzd1c0SLB0UzyUiLUyBJi85EK0MoSANTKEjHRCQgAAAAAP9TSIXAdCM93RAAAHQci8BIiUQkOItTEEyNRCQwSItLCEG5BAAAAP9TQEiLdCRoSItsJGBIi3wkcEiLXCR4SIPEUEFew0iLczBIjXswTDvGcpBIA/ZMi0MgTIvOSItLGDPS/1M4SIXAdAxIiUMgSIk36Wz///+F7Q+EZP///0jHRCQ4DgAHgOuM']
			DllCall('crypt32\CryptStringToBinary', 'str', hex := mcodes[A_PtrSize >> 2], 'uint', 0, 'uint', 1, 'ptr', 0, 'uint*', &s := 0, 'ptr', 0, 'ptr', 0) &&
				DllCall('crypt32\CryptStringToBinary', 'str', hex, 'uint', 0, 'uint', 1, 'ptr', code := Buffer(s), 'uint*', &s, 'ptr', 0, 'ptr', 0) &&
				DllCall('VirtualProtect', 'ptr', code, 'uint', s, 'uint', 0x40, 'uint*', 0)
			return code
			/*c++ source, /FAc /O2 /GS-
			struct Context {
				void *obj;
				HWND hwnd;
				UINT msg;
				UINT initial_size;
				HANDLE heap;
				BYTE *data;
				size_t size;
				size_t capacity;
				decltype(&HeapReAlloc) ReAlloc;
				decltype(&SendMessageW) Send;
				decltype(&WinHttpWebSocketReceive) Receive;
			};
			void __stdcall WINHTTP_STATUS_READ_WRITE_COMPLETE(
				void *hInternet,
				Context *dwContext,
				DWORD dwInternetStatus,
				WINHTTP_WEB_SOCKET_STATUS *lpvStatusInformation,
				DWORD dwStatusInformationLength) {
				if (!dwContext)
					return;
				auto &context = *dwContext;
				if (dwInternetStatus == WINHTTP_CALLBACK_FLAG_WRITE_COMPLETE)
					return (void)context.Send(context.hwnd, context.msg, (WPARAM)dwContext, 5);
				else if (dwInternetStatus != WINHTTP_CALLBACK_FLAG_READ_COMPLETE)
					return;
				UINT_PTR param[3] = { (UINT_PTR)context.obj, 0 };
				DWORD err;
				switch (auto bt = lpvStatusInformation->eBufferType)
				{
				case WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE:
					goto close;
				default:
					size_t new_size;
					auto is_fragment = bt & 1;
					context.size += lpvStatusInformation->dwBytesTransferred;
					if (!is_fragment) {
						param[1] = (UINT_PTR)context.data;
						param[2] = context.size;
						context.size = 0;
						if (!context.Send(context.hwnd, context.msg, (WPARAM)param, bt) ||
							(new_size = (size_t)context.initial_size) == context.capacity)
							break;
					}
					else if (context.size >= context.capacity)
						new_size = context.capacity << 1;
					else break;
					if (auto p = context.ReAlloc(context.heap, 0, context.data, new_size))
						context.data = (BYTE *)p, context.capacity = new_size;
					else if (is_fragment) {
						param[1] = E_OUTOFMEMORY;
						goto close;
					}
					break;
				}
				err = context.Receive(hInternet, context.data + context.size, DWORD(context.capacity - context.size), 0, 0);
				if (err && err != ERROR_INVALID_OPERATION) {
					param[1] = err;
				close: context.Send(context.hwnd, context.msg, (WPARAM)param, WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE);
				}
			}*/
		}

		static receive(*) {
			Throw WebSocket.Error('Used only in synchronous mode')
		}
	}

	/**
	 * @public
	 * Consulta el código y motivo de cierre enviados por el servidor.
	 * @returns {Object} Con el `status` y `reason`.
	 */
	queryCloseStatus() {
		if (!DllCall('Winhttp\WinHttpWebSocketQueryCloseStatus', 'ptr', this, 'ushort*', &usStatus := 0, 'ptr', vReason := Buffer(123), 'uint', 123, 'uint*', &len := 0))
			return { status: usStatus, reason: StrGet(vReason, len, 'utf-8') }
		else if (this.readyState > 1)
			return { status: 1006, reason: '' }
	}

	/**
	 * @private
	 * Envía un frame WebSocket de bajo nivel.
	 * @param {Integer} type Tipo de frame (texto o bonario):
	 * - `0` → BINARY_MESSAGE
	 * - `1` → BINARY_FRAGMENT
	 * - `2` → UTF8_MESSAGE
	 * - `3` → UTF8_FRAGMENT
	 * @param {Integer} buf Puntero al buffer.
	 * @param {Integer} size Tamaño en bytes.
	 */
	_send(type, buf, size) {
		if (this.readyState != 1)
			Throw WebSocket.Error('websocket is disconnected')
		if err := DllCall('Winhttp\WinHttpWebSocketSend', 'ptr', this, 'uint', type, 'ptr', buf, 'uint', size, 'uint')
			return this.onError(err)
	}

	/**
	 * @public
	 * Envía una cadena de texto codificada en UTF-8 al servidor.
	 * @param {String} str Cadena UTF-8 a enviar.
	 */
	sendText(str) {
		if (size := StrPut(str, 'utf-8') - 1) {
			StrPut(str, buf := Buffer(size), 'utf-8')
			this._send(2, buf, size)
		} else
			this._send(2, 0, 0)
	}

	/**
	 * @public
	 * Envía datos binarios.
	 * @param {Buffer} buf Buffer con los datos a transmitir.
	 */
	send(buf) => this._send(0, buf, buf.Size) ;

	/**
	 * @public
	 * Recibe un mensaje del servidor de forma bloqueante.
	 * @returns {void | String | Buffer} `String` si es un mensaje de texto, o
	 * `Buffer` si es binario.
	 * @throws {Error} Si se utiliza en modo asíncrono.
	 */
	receive() {
		if (this.readyState != 1)
			Throw WebSocket.Error('websocket is disconnected')
		ptr := (cache := Buffer(size := this.__cache_size)).Ptr, offset := 0
		while (!err := DllCall('Winhttp\WinHttpWebSocketReceive', 'ptr', this, 'ptr', ptr + offset, 'uint', size - offset, 'uint*', &dwBytesRead := 0, 'uint*', &eBufferType := 0)) {
			switch eBufferType {
				case 1, 3:
					offset += dwBytesRead
					if offset == size
						cache.Size := size *= 2, ptr := cache.Ptr
				case 0, 2:
					offset += dwBytesRead
					if eBufferType == 2
						return StrGet(ptr, offset, 'utf-8')
					cache.Size := offset
					return cache
				case 4:
					rea := this.QueryCloseStatus(), this.shutdown()
					try this.onClose(rea.status, rea.reason)
					return
			}
		}
		(err != 4317 && this.onError(err))
	}

	/**
	 * @public
	 * Cierra la conexión WebSocket de forma controlada.
	 * Envía un frame `CLOSE`, actualiza el estado y libera los handlers asociados.
	 */
	shutdown() {
		if (this.readyState = 1) {
			this.readyState := 2
			DllCall('Winhttp\WinHttpWebSocketClose', 'ptr', this, 'ushort', 1006, 'ptr', 0, 'uint', 0)
			this.readyState := 3
		}
		while (this.HINTERNETs.Length > 2)
			DllCall('Winhttp\WinHttpCloseHandle', 'ptr', this.HINTERNETs.Pop())
		this.Ptr := 0
	}

	/**
	 * 
	 * @private
	 * Destructor automático del objeto:
	 * - Cierra la conexión si sigue activa.
	 * - Libera todos los handles WinHTTP.
	 * - Evita fugas de memoria.
	 */
	__Delete() {
		this.shutdown()
		while (this.HINTERNETs.Length)
			DllCall('Winhttp\WinHttpCloseHandle', 'ptr', this.HINTERNETs.Pop())
	}

	/**
	 * @private
	 * Maneja errores WinHTTP:
	 * - Traduce códigos de error a mensajes legibles.
	 * - Gestiona cierres anómalos.
	 * - Lanza excepciones cuando corresponde.
	 */
	onError(err, what := 0) {
		if err != 12030
			Throw WebSocket.Error(err, what - 5)
		if this.readyState == 3
			return
		this.readyState := 3
		try this.onClose(1006, '')
	}

	/**
	 * @private
	 * Traduce códigos de error WinHTTP a mensajes descriptivos
	 * y permite distinguir errores de red, protocolo y estado.
	 */
	class Error extends Error 
    {
		__New(err := A_LastError, what := -4)
        {
			static module := DllCall('GetModuleHandle', 'str', 'winhttp', 'ptr')
			if err is Integer
				if (DllCall("FormatMessage", "uint", 0x900, "ptr", module, "uint", err, "uint", 0, "ptr*", &pstr := 0, "uint", 0, "ptr", 0), pstr)
					err := (msg := StrGet(pstr), DllCall('LocalFree', 'ptr', pstr), msg)
				else err := OSError(err).Message
			super.__New(err, what)
		}
	} ;
}