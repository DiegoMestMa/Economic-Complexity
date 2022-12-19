clear all
set more off
capture log close

******
* 1. Establecer carpetas de trabajo
******

global o1 "C:/Users/Diego/OneDrive/Escritorio/IDIC 2022/"

global o2 "$o1/1 Bases de Datos/"

global o3 "$o1/2 Resultados/"

global paises_lista 1 "AUS" 2 "AUT" 3 "BEL" 4 "CAN" 5 "CHL" 6 "COL" 7 "CRI" 8 "CZE" 9 "DNK" 10 "EST" 11 "FIN" 12 "FRA" 13 "DEU" 14 "GRC" 15 "HUN" 16 "ISL" 17 "IRL" 18 "ISR" 19 "ITA" 20 "JPN" 21 "KOR" 22 "LVA" 23 "LTU" 24 "LUX" 25 "MEX" 26 "NLD" 27 "NZL" 28 "NOR" 29 "POL" 30 "PRT" 31 "SVK" 32 "SVN" 33 "ESP" 34 "SWE" 35 "CHE" 36 "TUR" 37 "GBR" 38 "USA" 39 "ARG" 40 "BRA" 41 "BRN" 42 "BGR" 43 "KHM" 44 "CHN" 45 "HRV" 46 "CYP" 47 "IND" 48 "IDN" 49 "HKG" 50 "KAZ" 51 "LAO" 52 "MYS" 53 "MLT" 54 "MAR" 55 "MMR" 56 "PER" 57 "PHL" 58 "ROU" 59 "RUS" 60 "SAU" 61 "SGP" 62 "ZAF" 63 "TWN" 64 "THA" 65 "TUN" 66 "VNM" 67 "ROW"

* Establecer parametros
*********************
global indicador VADF /*VAX XB ID_V FD VBP*/
global paises 67
global sectores 45
global iteracionmax 100
*********************

******
* 2. Estimar VXF, por año
******
	forv anio=1995(1)1995{
		use "$o3/ICIO/Dataset_2.dta", clear	
		
		drop if anio != `anio'
		keep pais sector $indicador
	
		reshape wide $indicador, i(pais) j(sector)
	
		mata: VX = st_data(., "$indicador*")
		mata: EVX = colsum(VX)
		mata: W = VX :/ EVX
		
		/*Crear vectores con valores iniciales*/
		mata: Fhat = J(rows(VX),1,1)
		mata: VXF = J(rows(VX),1,1)
		
		mata: Qhat = J(cols(VX),1,1)
		mata: Q = J(cols(VX),1,1)
		
		forv iteracion=1(1)$iteracionmax {		
				mata: VXFn_1 = VXF				
				forv i=1(1)$paises {
					mata: Fhat[`i',.] = sum(W[`i',.]:*Q')
					mata: VXF[`i',.] = Fhat[`i',.]/(1/rows(VX)*sum(Fhat))
				}				
				forv i=1(1)$sectores {
					mata: Qhat[`i',.] = 1/(sum(W[.,`i']:*(1:/VXFn_1)))		
					mata: Q[`i',.] = Qhat[`i',.]/(1/cols(VX)*sum(Qhat))			
				}	
			}
	
		gen anio = `anio'
		getmata VXF
		keeporder anio pais VXF
		
		gsort - VXF
		
		save "$o3/VXF/VXF_`anio'", replace

	}

/* Realizar panel data */
	clear all

	use "$o3/VXF/VXF_1995", clear

	forv anio=1996(1)2018{
		
		append using "$o3/VXF/VXF_`anio'"
		
		
	}

	save "$o3/VXF/VXF_1995-2018", replace
