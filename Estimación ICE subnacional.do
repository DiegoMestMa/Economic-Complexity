clear all
set more off
capture log close
*set matsize 800
******
* 1. Establecer carpetas de trabajo
******

global o1 "C:/Users/Diego/OneDrive/Escritorio/IDIC 2022/"

global o2 "$o1/1 Bases de Datos/ICE"

global o3 "$o1/2 Resultados/ICE"

***********************
*local rca 1
*local rpop 0.25
***********************

******
* 0. Manejar bases de Mincetur y de Harvard
******
	**Mincetur
	import excel "$o2/ICE departamentos/Xs Perú por región origen - 2002 a 2021-Mincetur.xlsx", firstrow sheet("Base") clear
	
	rename Año anio
	rename Cód_ubigeo location_id
	rename Región departamento
	rename CodPaís pais_exp_id
	rename País desc_pais_exp
	rename Partida_arancelaria hs_product_code
	rename Desc_partida desc_product
	rename HS_partida hs
	rename FOB export_value
	rename Peso_Neto peso_neto
	
	*destring location_id, replace
	*destring product_id, replace
	/* 
	//Calcular participacion por region
	collapse (sum) export_value, by(location_id)
	egen total_pais = total(export_value)
	gen part = export_value/total_pais
	*/
	
	drop if location_id == "" // Sin ubigeo [Verificar: valor monetario]
	replace hs_product_code = substr(product_id, 1, 4) //generar HS 4
	
	save "$o2/ICE departamentos/Xs Perú por región origen - 2002 a 2021-Mincetur.dta", replace

	**Harvard
	clear all
	forv anio=2014(1)2014{
		
		use "$o2/ICE paises/Harvard/dataverse_files/country_partner_hsproduct4digit_year_`anio'.dta", clear
	
		collapse (sum) export_value, by(year hs_product_code)		
		
		save "$o3/ICE paises/Insumos para ICE departamentos/country_partner_hsproduct4digit_year_`anio'_colapsada.dta", replace
		
	}
	
******
* 1. Crear matriz binaria de VCR, estimar ECI y PCI
******

**MÉTODO 1 [VCR con exportaciones subnacionales ajustados por internacionales y PCI exógeno (https://oec.world/en/resources/methods#eci-subnational)]
	*1. Con datos de PCI de Harvard y propios
	clear all
	forv anio=2014(1)2014{

	use "$o2/ICE departamentos/Xs Perú por región origen - 2002 a 2021-Mincetur.dta", clear
	
	keep location_id departamento hs_product_code anio export_value
	rename export_value export_value_dep
	drop if anio != `anio'
	
	*collapse (sum) export_value, by(anio location_id hs_product_code)
	
	/*merge m:1 hs_product_code using "$o3/ICE paises/PCI_`anio'.dta", keepusing(pci)
	drop if _merge != 3 //2002: no se unen 446 departamento-producto. La mitad corresponde a la base Mincetur y la otra, a la base de PCI. 990 productos y 25 departamentos
	drop _merge*/
		
	/* Unir PCI de Harvard */
	destring hs_product_code, generate(hs_product_code_destring)
	
	merge m:1 anio hs_product_code_destring using "$o2/ICE paises/PCI_Harvard.dta", keepusing(pci_harvard)
	drop if _merge != 3
	drop hs_product_code_destring _merge
	
	/* Unir Exportaciones del mundo de Harvard */
	merge m:1 hs_product_code using "$o3/ICE paises/Insumos para ICE departamentos/country_partner_hsproduct4digit_year_`anio'_colapsada.dta", keepusing(export_value)
	preserve
	
	/* Extraer la exportaciones totales de mundo */
	collapse (mean) export_value, by(hs_product_code)		
	
	mata: EcpXcp_1 = st_data(., "export_value")
	mata: EcpXcp = sum(EcpXcp_1)

	restore
	
	drop if _merge != 3 //2002: no se unen 253 departamento-producto. Todos corresponden a la base colapsada de Harvard
	drop _merge
	// [Nota: utilizar PCI calculados y de OEC]
	// [Falta: validar que los productos unidos tengan la misma descripción]
	// [Preguntar: Para hacer la matriz binaria, debemos mantener la cantidad de productos total o es irrelevante para el cálculo. Perú exporta pocos productos. Podría ser relevante para tener el total de exportaciones mundiales (aunque igual no estarían todos los productos si utilizamos la lista que tenemos)]
	
	preserve

	*1. Subir matrices a Mata

	/* Matriz de exportaciones pais-producto */ 
	collapse (sum) export_value_dep, by(hs_product_code location_id)


	rename export_value_dep Xcp
	fillin location_id hs_product_code
	replace Xcp = 0 if Xcp == .
	drop _fillin

	reshape wide Xcp, i(location_id) j(hs_product_code) string

	*order location_id Xcp0* Xcp1* Xcp2* Xcp3* Xcp4* Xcp5* Xcp6* Xcp7* Xcp8* Xcp9* /* ordenar las variables (cod producto) de menor a mayor */

	mata:  Xcp = st_data(., "Xcp*")
	
	destring location_id, replace
	mata: location_id = st_data(., "location_id")
	/*
	/* Vector de exportaciones por departamento */ 
	
	[Nota: esto se puede hacer como suma hacia la derecha de la matriz Xcp]

	*reshape long Xcp, i(location_id) j(product_id)
	restore, preserve

	collapse (sum) export_value, by(location_id)
	rename export_value EcXcp	

	mkmat location_id, matrix(location_id) //subir vector de departamentos
	*mkmat EcXcp, matrix(EcXcp)
	*mata: EcXcp = st_matrix("EcXcp")
	mata:  EcXcp = st_data(., "EcXcp")
	*/
	
	/* Vector de exportaciones de Países por producto */
	restore, preserve
	
	collapse (mean) export_value, by(hs_product_code)
	rename export_value EcXcp	
	
	mata: hs_product_code = st_data(., "hs_product_code") //subir vector de productos
	mata:  EcXcp = st_data(., "EcXcp")

	/* Vector de PCI de Países por producto */
	restore, preserve
	
	collapse (mean) pci_harvard, by(hs_product_code)
	
	mata:  pci_harvard = st_data(., "pci_harvard")
	
	restore
	
	/*
	/* Vector de exportaciones por producto */
	
	[Nota: esto se puede hacer como suma hacia abajo de la matriz Xcp]

	restore, preserve

	collapse (sum) export_value, by(hs_product_code)
	rename export_value EpXcp	

	*mkmat product_id, matrix(product_id)
	*mkmat EpXcp, matrix(EpXcp)
	*mata: EpXcp = st_matrix("EpXcp")

	mata:  product_id = st_data(., "product_id")
	mata:  EpXcp = st_data(., "EpXcp")
	/* Vector de exportaciones totales */
	restore

	collapse (sum) export_value
	rename export_value EcpXcp	

	mkmat EcpXcp, matrix(EcpXcp)
	mata: EcpXcp = st_matrix("EcpXcp")
	*/
	*2. Cálculo de la matriz Mcp

	mata: Mcp = (Xcp:/rowsum(Xcp)):/(EcXcp:/EcpXcp)'
	// [Nota: agregar exportaciones mundiales]
	
	mata: Mcp = Mcp :>= 1
	
	/*mata{	
		for (i=1;i<=rows(Mcp);i++){
			for (j=1;j<=cols(Mcp);j++){
				if (Mcp[i,j] >= 1) Mcp[i,j] = 1
				if (Mcp[i,j] < 1) Mcp[i,j] = 0						
			}
		}	
	}*/
	// [Nota: evaluar dejar de utilizar un corte para Mcp, o probar otros cortes]
	
	//[Nota: ordenar EcXcp para que el lugar de cada producto esté igual al que tiene en la matriz Xcp [Ya está ordenado, pero igual validar]]
	
	/*mata{

	Mcp = J(rows(Xcp),cols(Xcp),.)

	for (i=1;i<=rows(Xcp);i++){
		for (j=1;j<=cols(Xcp);j++){

			Mcp[i,j] = (Xcp[i,j]/EcXcp[i,.])/(EpXcp[j,.]/EcpXcp)

			if (Mcp[i,j] >= 1) Mcp[i,j] = 1
			if (Mcp[i,j] < 1) Mcp[i,j] = 0

		}
	}*/

	*3. Generación del ECI
	
	mata: kc0 = rowsum(Mcp) /* Diversidad */
	mata: kp0 = colsum(Mcp) /* Ubicuidad */
	
	mata: eci = (1:/kc0):*rowsum(Mcp:*pci_harvard')
	
	mata: location_id_2 = location_id
	collapse (sum) export_value_dep, by(location_id departamento) 
	keep location_id departamento
	getmata location_id_2 eci

	tempvar aux1 aux2
	egen `aux1' = sd(eci)
	egen `aux2' = mean(eci)
	replace eci = (eci-`aux2')/`aux1'
	drop `aux1' `aux2'
	
	gsort - eci
	}	
	
	*2. Con datos de PCI del OEC

**MÉTODO 2 [VCR con exportaciones subnacionales y PCI exógeno]
	*1. Con datos de PCI propios
	*2. Con datos de PCI del OEC

**MÉTODO 3 [VCR con exportaciones subnacionales y PCI endógeno]	
	clear all
	forv anio=2014(1)2014{

	use "$o2/ICE departamentos/Xs Perú por región origen - 2002 a 2021-Mincetur.dta", clear
	
	keep location_id departamento hs_product_code anio export_value
	drop if anio != `anio'
		
	preserve

	*1. Subir matrices a Mata

	/* Matriz de exportaciones pais-producto */ 
	collapse (sum) export_value, by(hs_product_code location_id)


	rename export_value Xcp
	fillin location_id hs_product_code
	replace Xcp = 0 if Xcp == .
	drop _fillin

	reshape wide Xcp, i(location_id) j(hs_product_code) string

	*order location_id Xcp0* Xcp1* Xcp2* Xcp3* Xcp4* Xcp5* Xcp6* Xcp7* Xcp8* Xcp9* /* ordenar las variables (cod producto) de menor a mayor */

	mata:  Xcp = st_data(., "Xcp*")
	
	destring location_id, replace
	mata: location_id = st_data(., "location_id")
	
	restore
	/* Vector de exportaciones por departamento */ 
	
	// [Nota: esto se puede hacer como suma hacia la derecha de la matriz Xcp]

	mata: EpXcp = rowsum(Xcp)
	
	/* Vector de exportaciones por producto */
	
	// [Nota: esto se puede hacer como suma hacia abajo de la matriz Xcp]

	mata: EcXcp = colsum(Xcp)

	/* Vector de exportaciones totales */

	mata: EcpXcp = sum(Xcp)
	
	*2. Cálculo de la matriz Mcp

	mata: Mcp = (Xcp:/rowsum(Xcp)):/(colsum(Xcp):/sum(Xcp))
	
	mata{	
		for (i=1;i<=rows(Mcp);i++){
			for (j=1;j<=cols(Mcp);j++){
				if (Mcp[i,j] >= 1) Mcp[i,j] = 1
				if (Mcp[i,j] < 1) Mcp[i,j] = 0						
			}
		}	
	}
	// [Nota: evaluar dejar de utilizar un corte para Mcp, o probar otros cortes]
	
	//[Nota: ordenar EcXcp para que el lugar de cada producto esté igual al que tiene en la matriz Xcp [Ya está ordenado, pero igual validar]]

	*3. Generación del ECI
	
	mata: kc0 = rowsum(Mcp) /* Diversidad */
	mata: kp0 = colsum(Mcp) /* Ubicuidad */
	
	mata: D = diag(kc0)
	mata: U = diag(kp0)

	mata: S = Mcp*pinv(U)*Mcp'
	mata: Mcc = pinv(D)*S

	mata: eigensystem(Mcc,Vc=.,lc=.)
	mata: kc = Re(Vc[.,2]) 

	*checksign = 2*((kc[41,.]) > 0 ) - 1
	// [Nota: evaluar si se debería hacer un checksign]

	*kc=kc :* checksign
	
	mata: location_id_2 = location_id
	mata: eci = kc
	collapse (sum) export_value, by(location_id departamento) 
	keep location_id departamento
	getmata location_id_2 eci

	tempvar aux1 aux2
	egen `aux1' = sd(eci)
	egen `aux2' = mean(eci)
	replace eci = (eci-`aux2')/`aux1'
	drop `aux1' `aux2'
	
	gsort - eci
	}	
		
******
* 5. Juntar ECI departamentos en formato panel
******	

	*1. ECI

	/* colocar año a cada data set */
	forv anio=1995(1)2020{
		
		use "$o3/ICE_`anio'", clear
		gen year = `anio'
		order year
		
		save "$o3/ICE_`anio'", replace
	} 

	/* append data set */

	use "$o3/ICE_1995", clear

	forv anio=1996(1)2020{
		
		append using "$o3/ICE_`anio'"
		
	} 

	save "$o3/ICE_1995-2020", replace
