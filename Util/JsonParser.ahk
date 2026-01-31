#Requires AutoHotkey v2.0

/************************************************************************
 * @brief Utilidad para convertir entre cadenas JSON y estructuras de AutoHotkey.
 *
 * Soporta:
 * - Objetos, arrays y valores primitivos.
 * - true, false y null preservando tipos.
 *
 * Implementa `parse()` para deserializar y `stringify()` para serializar.
 * 
 * Modificación de [thqby/ahk2_lib](https://github.com/thqby/ahk2_lib/blob/master/JSON.ahk).
 * 
 * @author bitasuperactive
 * @date 31/01/2026
 * @version 1.1.0
 ***********************************************************************/
class JsonParser 
{
	/**
	 * @public
	 * Valor nulo en JSON.
	 */
	static null := ComValue(1, 0) ;

	/**
	 * @public
	 * Valor verdadero en JSON.
	 */
	static true := ComValue(0xB, 1) ;

	/**
	 * @public
	 * Valor falso en JSON.
	 */
	static false := ComValue(0xB, 0) ;
	
	/**
	 * @public
	 * @author thqby, HotKeyIt
	 * @brief Convierte un texto JSON válido en un objeto AutoHotkey.
	 * @param {String} json Cadena JSON válida.
	 * @param {Boolean} keepbooltype (Opcional) Si es verdadero, convierte los valores booleanos
	 * en sus respectivos equivalentes JSON. En caso contrario, mantiene su valor nativo de AHK.
	 * Por defecto: `false`.
	 * @param {Boolean} as_map (Opcional) Si es verdadero, los objetos JSON se convierten en `Map`.
	 * En caso contrario, se convierten en `Object`. Por defecto: `true`.
	 * @returns {Array|Map|Object} Estructura equivalente al JSON proporcionado.
	 * @throws {Error} Si el texto JSON está mal formado.
	 */
	static Parse(json, keepbooltype := false, as_map := true) 
	{
		keepbooltype ? (_true := this.true, _false := this.false, _null := this.null) : (_true := true, _false := false, _null := "")
		as_map ? (map_set := (maptype := Map).Prototype.Set) : (map_set := (obj, key, val) => obj.%key% := val, maptype := Object)
		NQ := "", LF := "", LP := 0, P := "", R := ""
		D := [C := (A := InStr(json := LTrim(json, " `t`r`n"), "[") = 1) ? [] : maptype()], json := LTrim(SubStr(json, 2), " `t`r`n"), L := 1, N := 0, V := K := "", J := C, !(Q := InStr(json, '"') != 1) ? json := LTrim(json, '"') : ""
		Loop Parse json, '"' {
			Q := NQ ? 1 : !Q
			NQ := Q && RegExMatch(A_LoopField, '(^|[^\\])(\\\\)*\\$')
			if !Q {
				if (t := Trim(A_LoopField, " `t`r`n")) = "," || (t = ":" && V := 1)
					continue
				else if t && (InStr("{[]},:", SubStr(t, 1, 1)) || A && RegExMatch(t, "m)^(null|false|true|-?\d+(\.\d*(e[-+]\d+)?)?)\s*[,}\]\r\n]")) {
					Loop Parse t {
						if N && N--
							continue
						if InStr("`n`r `t", A_LoopField)
							continue
						else if InStr("{[", A_LoopField) {
							if !A && !V
								throw Error("Malformed JSON - missing key.", 0, t)
							C := A_LoopField = "[" ? [] : maptype(), A ? D[L].Push(C) : map_set(D[L], K, C), D.Has(++L) ? D[L] := C : D.Push(C), V := "", A := Type(C) = "Array"
							continue
						} else if InStr("]}", A_LoopField) {
							if !A && V
								throw Error("Malformed JSON - missing value.", 0, t)
							else if L = 0
								throw Error("Malformed JSON - to many closing brackets.", 0, t)
							else C := --L = 0 ? "" : D[L], A := Type(C) = "Array"
						} else if !(InStr(" `t`r,", A_LoopField) || (A_LoopField = ":" && V := 1)) {
							if RegExMatch(SubStr(t, A_Index), "m)^(null|false|true|-?\d+(\.\d*(e[-+]\d+)?)?)\s*[,}\]\r\n]", &R) && (N := R.Len(0) - 2, R := R.1, 1) {
								if A
									C.Push(R = "null" ? _null : R = "true" ? _true : R = "false" ? _false : IsNumber(R) ? R + 0 : R)
								else if V
									map_set(C, K, R = "null" ? _null : R = "true" ? _true : R = "false" ? _false : IsNumber(R) ? R + 0 : R), K := V := ""
								else throw Error("Malformed JSON - missing key.", 0, t)
							} else {
								; Added support for comments without '"'
								if A_LoopField == '/' {
									nt := SubStr(t, A_Index + 1, 1), N := 0
									if nt == '/' {
										if nt := InStr(t, '`n', , A_Index + 2)
											N := nt - A_Index - 1
									} else if nt == '*' {
										if nt := InStr(t, '*/', , A_Index + 2)
											N := nt + 1 - A_Index
									} else nt := 0
									if N
										continue
								}
								throw Error("Malformed JSON - unrecognized character.", 0, A_LoopField " in " t)
							}
						}
					}
				} else if A || InStr(t, ':') > 1
					throw Error("Malformed JSON - unrecognized character.", 0, SubStr(t, 1, 1) " in " t)
			} else if NQ && (P .= A_LoopField '"', 1)
				continue
			else if A
				LF := P A_LoopField, C.Push(InStr(LF, "\") ? UC(LF) : LF), P := ""
			else if V
				LF := P A_LoopField, map_set(C, K, InStr(LF, "\") ? UC(LF) : LF), K := V := P := ""
			else
				LF := P A_LoopField, K := InStr(LF, "\") ? UC(LF) : LF, P := ""
		}
		return J
		UC(S, e := 1) {
			static m := Map('"', '"', "a", "`a", "b", "`b", "t", "`t", "n", "`n", "v", "`v", "f", "`f", "r", "`r")
			local v := ""
			Loop Parse S, "\"
				if !((e := !e) && A_LoopField = "" ? v .= "\" : !e ? (v .= A_LoopField, 1) : 0)
					v .= (t := m.Get(SubStr(A_LoopField, 1, 1), 0)) ? t SubStr(A_LoopField, 2) :
						(t := RegExMatch(A_LoopField, "i)^(u[\da-f]{4}|x[\da-f]{2})\K")) ?
							Chr("0x" SubStr(A_LoopField, 2, t - 2)) SubStr(A_LoopField, t) : "\" A_LoopField,
							e := A_LoopField = "" ? e : !e
			return v
		}
	}

	/**
	 * @public
	 * @author thqby, HotKeyIt
	 * @brief Convierte un `Array`/`Map`/`Object` plano de AutoHotkey a texto JSON.
	 * @warning No soporta la serialización de objetos custom anidados.
	 * @note Las claves y propiedades añaden un guión bajo (`_`) al inicio obligatoriamente.
	 * @param {Any} obj Valor (normalmente un objeto, collección o mapa) a serializar.
	 * @param {Integer} expandlevel (Opcional) Profundidad máxima que se expandirá.
	 * Por defecto: Expande completamente.
	 * @param {String} space (Opcional) Añade sangrías o espacios al resultado
	 * para mejorar su legibilidad. Por defecto: Dos espacios por nivel.
	 * @returns {String} Texto JSON equivalente al objeto.
	 */
	static Stringify(obj, expandlevel := unset, space := "  ") 
	{
		expandlevel := IsSet(expandlevel) ? Abs(expandlevel) : 10000000
		return Trim(CO(obj, expandlevel))


		CO(O, J := 0, R := 0, Q := 0) {
			static M1 := "{", M2 := "}", S1 := "[", S2 := "]", N := "`n", C := ",", S := "- ", E := "", K := ":"
			if (OT := Type(O)) = "Array" {
				D := !R ? S1 : ""
				for key, value in O {
					F := (VT := Type(value)) = "Array" ? "S" : InStr("Map,Object", VT) ? "M" : E
					Z := VT = "Array" && value.Length = 0 ? "[]" : ((VT = "Map" && value.count = 0) || (VT = "Object" && ObjOwnPropCount(value) = 0)) ? "{}" : ""
					D .= (J > R ? "`n" CL(R + 2) : "") (F ? (%F%1 (Z ? "" : CO(value, J, R + 1, F)) %F%2) : ES(value)) (OT = "Array" && O.Length = A_Index ? E : C)
				}
			} else {
				D := !R ? M1 : ""
				for key, value in (OT := Type(O)) = "Map" ? (Y := 1, O) : (Y := 0, O.OwnProps()) {
					F := (VT := Type(value)) = "Array" ? "S" : InStr("Map,Object", VT) ? "M" : E
					Z := VT = "Array" && value.Length = 0 ? "[]" : ((VT = "Map" && value.count = 0) || (VT = "Object" && ObjOwnPropCount(value) = 0)) ? "{}" : ""
					D .= (J > R ? "`n" CL(R + 2) : "") (Q = "S" && A_Index = 1 ? M1 : E) ES(key) K (F ? (%F%1 (Z ? "" : CO(value, J, R + 1, F)) %F%2) : ES(value)) (Q = "S" && A_Index = (Y ? O.count : ObjOwnPropCount(O)) ? M2 : E) (J != 0 || R ? (A_Index = (Y ? O.count : ObjOwnPropCount(O)) ? E : C) : E)
					if J = 0 && !R
						D .= (A_Index < (Y ? O.count : ObjOwnPropCount(O)) ? C : E)
				}
			}
			if J > R
				D .= "`n" CL(R + 1)
			if R = 0
				D := RegExReplace(D, "^\R+") (OT = "Array" ? S2 : M2)
			return D
		}

		ES(S) {
			switch Type(S) {
				case "Float":
					if (v := '', d := InStr(S, 'e'))
						v := SubStr(S, d), S := SubStr(S, 1, d - 1)
					if ((StrLen(S) > 17) && (d := RegExMatch(S, "(99999+|00000+)\d{0,3}$")))
						S := Round(S, Max(1, d - InStr(S, ".") - 1))
					return S v
				case "Integer":
					return S
				case "String":
					S := StrReplace(S, "\", "\\")
					S := StrReplace(S, "`t", "\t")
					S := StrReplace(S, "`r", "\r")
					S := StrReplace(S, "`n", "\n")
					S := StrReplace(S, "`b", "\b")
					S := StrReplace(S, "`f", "\f")
					S := StrReplace(S, "`v", "\v")
					S := StrReplace(S, '"', '\"')
					S := (
						replace := SubStr(S, 1, 1) = '_',
						chUpper := StrUpper(SubStr(S, 2, 1)),
						!replace ? S : chUpper . SubStr(S, 3)
					) ;// added by bitasuperactive to avoid starting keys with '_'
					return '"' S '"'
				default:
					return S == this.true ? "true" : S == this.false ? "false" : "null"
			}
		}

		CL(i) {
			Loop (s := "", space ? i - 1 : 0)
				s .= space
			return s
		}
	}

	/**
	 * @public
	 * @brief Convierte un Array/Map/Object (con anidación) a JSON.
	 * - Permite la serialización de objetos custom anidados.
	 * @author ChatGPT (based on thqby's code)
	 * @note Los guiones bajos (`_`) al inicio de las claves y propiedades serán eliminados.
	 * @param {Any} val Valor (normalmente un objeto, colección o mapa) a serializar.
	 * @param {Integer} maxDepth (Opcional) Profundidad máxima que se expandirá.
	 * Por defecto: Expande completamente.
	 * @param {String} indentation (Opcional) Sangrías o espacios a añadir al resultado
	 * para mejorar su legibilidad. Por defecto: Una sangría por nivel.
	 * @param {Boolean} keyUnderscore (Opcional) Si es verdadero, mantiene o añade guiones bajos (`_`)
	 * al inicio de las claves y propiedades, lo que puede ser útil para garantizar la compatibilidad
	 * con APIs. Si es falso, los elimina y hace mayúscula la primera letra. Por defecto: `true`.
	 * @returns {String} Texto JSON equivalente al objeto.
	 */
	static Stringify2(val, maxDepth := unset, indentation := "    ", keyUnderscore := true)
	{
		maxDepth := IsSet(maxDepth) ? Abs(maxDepth) : 0x7FFFFFFF
		return SerializeValue(val, 0)


		SerializeValue(val, depth)
		{
			if (depth >= maxDepth)
				return "null"

			if (IsObject(val)) {
				return (Type(val) = "Array") ? SerializeArray(val, depth + 1) : SerializeObject(val, depth + 1)
			}
			else {
				return EncodeScalar(val)
			}
		}

		SerializeArray(arr, depth)
		{
			if (arr.Length = 0)
				return "[]"

			json := "["
			for index, item in arr
			{
				json .= "`n" Indent(depth)
				json .= SerializeValue(item, depth)

				if (index < arr.Length)
					json .= ","
			}

			json .= "`n" Indent(depth - 1) "]"
			return json
		}

		SerializeObject(val, depth)
		{
			nItems := (Type(val) = "Map") ? val.Count : ObjOwnPropCount(val)

			if (nItems = 0)
				return "{}"

			json := "{"

			for key, value in (Type(val) = "Map" ? val : val.OwnProps())
			{
				json .= "`n" Indent(depth)
				json .= EncodeKey(key) ": "
				json .= SerializeValue(value, depth)

				if (A_Index < nItems)
					json .= ","
			}

			json .= "`n" Indent(depth - 1) "}"
			return json
		}

		EncodeKey(key)
		{
			; Eliminar '_' solo en claves
			if (keyUnderscore = false && SubStr(key, 1, 1) = "_")
				key := StrUpper(SubStr(key, 2, 1)) SubStr(key, 3)

			return EncodeString(key)
		}

		EncodeScalar(value)
		{
			switch Type(value)
			{
				case "Integer":
					return value

				case "Float":
					return value

				case "String":
					return EncodeString(value)

				default:
					return (
						(value = true) ? "true"
						: (value = false) ? "false"
						: "null"
					)
			}
		}

		EncodeString(str)
		{
			str := StrReplace(str, "\", "\\")
			str := StrReplace(str, "`t", "\t")
			str := StrReplace(str, "`r", "\r")
			str := StrReplace(str, "`n", "\n")
			str := StrReplace(str, "`b", "\b")
			str := StrReplace(str, "`f", "\f")
			str := StrReplace(str, "`v", "\v")
			str := StrReplace(str, '"', '\"')

			return '"' str '"'
		}

		Indent(level)
		{
			out := ""
			Loop level
				out .= indentation
			return out
		}
	}
}