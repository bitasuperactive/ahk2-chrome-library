#Requires AutoHotkey v2.0

/************************************************************************
 * @class ProcessWMIWatcher
 * @brief
 * Clase que monitoriza la creación y eliminación de proceso individuales.
 * Para ello utiliza eventos WMI (`__InstanceCreationEvent` y `__InstanceDeletionEvent`)
 * sin bloquear el hilo principal.
 *
 * Esta clase se suscribe en modo asíncrono a WMI mediante `SWbemSink`,
 * ejecutando los callbacks indicados cuando el proceso objetivo aparece
 * o desaparece.
 * 
 * Ejemplo de uso:
 * @code
 * ProcessWMIWatcher("notepad.exe", (caller, state) => MsgBox("Estado del proceso: " state))
 * @endcode
 * @author bitasuperactive
 * @date 28/02/2026
 * @version 1.0.1
 * @see https://github.com/bitasuperactive/ahk2-chrome-library/blob/master/Util/ProcessWMIWatcher.ahk
 ***********************************************************************/
class ProcessWMIWatcher
{
    /** @private */
    _pName := unset ;
    /** @private */
    _eventHandler := unset ;
    /** @private */
    _wmi := unset ;
    /** @private */
    _sink := unset ;

    /**
     * @public
     * {String} Nombre del proceso monitorizado (con extensión `.exe`).
     */
    ProcessName => this._pName ;

    /**
     * @public
     * Establece un callback para la creación y destrucción del proceso indicado.
     * 
     * @warning Si la instancia no es liberada correctamente mediante `Dispose`, 
     * se pueden llegar a saturar los eventos WMI generando una infracción de cuotas.
     * 
     * @param {String} pName Nombre del proceso a monitorizar (con extensión `.exe`).
     * @param {Func<Boolean>} callback Función ejecutada al crearse o terminar un proceso.
     * Recibe un parámetro Boolean que será Verdadero si el proceso ha sido creado, o Falso
     * si ha sido finalizado.
     * @throws {Error} (0x8004106C) Si se produce una infracción de cuotas de WMI.
     */
    __New(pName, callback)
    {
        if (InStr(pName, ' ') || !InStr(pName, ".exe"))
            throw ValueError('El nombre del proceso "' pName '" no es válido.')
        if (!(callback is Func) || callback.MinParams != 2)
            throw ValueError('El callback no es válido. Debe ser una función con un único parámetro obligatorio.')

        this._pName := pName
        this._eventHandler := ProcessWMIWatcher._ProcessWMIEventHandler(callback)
        this._wmi := ComObjGet("winmgmts:")
        this._sink := ComObject("WbemScripting.SWbemSink")
        ComObjConnect(this._sink, this._eventHandler)
        
        command := "WITHIN 1  WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = '" this._pName "'"
        this._wmi.ExecNotificationQueryAsync(this._sink, "SELECT * FROM __InstanceCreationEvent " command)
        this._wmi.ExecNotificationQueryAsync(this._sink, "SELECT * FROM __InstanceDeletionEvent " command)
            
        OnExit((*) => this.Dispose())
    }

    /**
     * @public
     * Cancela la suscripción a eventos WMI y desconecta el sink.
     */
    Dispose()
    {
        try ComObjConnect(this._sink)
        try this._sink.Cancel()
        try this._wmi.CancelAsyncCall(this._sink)
    }

    /**
     * @private
     * Clase encargada de gestionar los eventos WMI asociados a la creación y eliminación
     * de un proceso específico. 
     * Esta clase actúa como manejador (event sink) para los eventos enviados por WMI mediante 
     * el objeto `SWbemSink`.
     */
    class _ProcessWMIEventHandler
    {
        /**
         * @private
         * Crea un manejador para los eventos de WMI para ProcessWMIWatcher.
         * @param {Func<Boolean>} callback Función ejecutada al crearse o terminar un proceso.
         * Recibe un parámetro Boolean que será Verdadero si el proceso ha sido creado, o Falso
         * si ha sido finalizado.
         */
        __New(callback)
        {
            this._callback := callback
        }

        /**
         * @private
         * Método invocado automáticamente por WMI cuando ocurre un evento.
         * @param {SWbemObject} Obj Contiene la información del evento.
         */
        OnObjectReady(obj, p*)
        {
            TI := obj.TargetInstance
            switch obj.Path_.Class
            {
                case "__InstanceCreationEvent":
                {
                    this._callback(true)
                }
                case "__InstanceDeletionEvent":
                {
                    ;// El número de procesos debe ser 0
                    if (!ProcessExist(TI.Name))
                        this._callback(false)
                }
            }
        }
    } ;
}