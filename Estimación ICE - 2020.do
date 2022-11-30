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
local rca 1
local rpop 0.25
***********************

******
* 2. Limpiar datos de poblacion
******

import excel "$o2/Population.xlsx", firstrow clear
drop TimeCode

rename PopulationtotalSPPOPTOTL population
rename CountryCode location_code

drop if population == ".."
destring population, replace
rename Time year
drop if missing(population)
destring year, replace

save "$o2/Population_clean", replace

drop if year != 2020

save "$o2/Population_clean_2020", replace

******
* 3. Seleccionar productos y paises
******

*0. Juntar bases de 1995-2020
forv anio=1996(1)2020{

append using "$o2/Harvard/dataverse_files/country_partner_hsproduct4digit_year_`anio'.dta"

}

save "$o2/Harvard/dataverse_files/country_partner_hsproduct4digit_year_1995-2020.dta", replace

*1. Subir base de 2020
use "$o2/Harvard/dataverse_files/country_partner_hsproduct4digit_year_2020.dta", clear

preserve

*2. Eliminar productos con valor exportado menor a 10 millones en 2020

collapse (sum) export_value, by(product_id hs_product_code)

drop if export_value < 10 * 1e6 /* 8 productos eliminados */

drop export_value
drop if hs_product_code == "XXXX" /* Trade data discrepancies */
drop if hs_product_code == "9999" /* Commodities not specified according to kind */
save "$o2/product_list", replace /* Lista final de productos: 1209 */

*3. Eliminar países con exportaciones menores a 1 billon en 2020 
restore /* restore solo funciona si se corre todo un bloque de código en donde se incluye el preserve previamente a este */

collapse (sum) export_value, by(location_id location_code)

drop if export_value < 1000 * 1e6 /* 83 países eliminados */

drop export_value

save "$o2/country_list", replace

*4. Eliminar países con población menor a 1.25 millon en 2018

use "$o2/country_list", clear

merge 1:1 location_code using "$o2/Population_clean_2020", keepusing(population) /* 2 paises de la lista inicial no tienen datos poblacionales: TWN (Taiwan) y ANS (Undeclared Countries). Se imputa el dato de Taiwan en 2020 */

replace population = 23561236 if location_code == "TWN"

drop _merge
drop if missing(population)
drop if missing(location_id) /* Se liminan las observaciones no emparejadas a excepción de TWN */
drop if population < 1.25 * 1e6 /* se eliminan 14 paises */
drop population

*Siguientes pasos: (i) eliminar a Chad, Iraq y Macau por posibles inconsistencias en el reporte. (ii) mantener solo países con datos de exportaciones para todos los años

save "$o2/country_list", replace /* Lista de paises: 137 */

* 5. Eliminar Chad, Iraq y Macao

use "$o2/country_list", clear

drop if location_code == "TCD"
drop if location_code == "IRQ"
drop if location_code == "MAC"

save "$o2/country_list", replace /* Lista de paises: 135 */

*6. Eliminar países que no presentan datos para todos los años de la muestra (1995-2020)
use "$o2/Harvard/dataverse_files/country_partner_hsproduct4digit_year_1995-2020.dta", clear

collapse (sum) export_value, by(location_id location_code year) /* demora cerca de 10 minutos en procesar. Se puede buscar otro procedimiento */

fillin location_id year

tab location_id if export_value == . /* Se encuentran 29 países sin exportaciones para todos los años: 6 10 11 20 27 36 37 55 86 94 95 98 129 131 144 150 154 155 181 184 189 193 198 201 202 209 210 229 233 */

foreach pais of numlist 6 10 11 20 27 36 37 55 86 94 95 98 129 131 144 150 154 155 181 184 189 193 198 201 202 209 210 229 233 {

drop if location_id == `pais' 

} /* se eliminan países sin exportaciones para todos los años*/

collapse (sum) export_value, by(location_id location_code)

merge 1:1 location_id location_code using "$o2/country_list"
keep if _merge == 3
drop _merge
drop export_value

save "$o2/country_list", replace /* Lista final de paises: 131 */

******
* 4. Crear matriz binaria de VCR, estimar ECI y PCI
******

forv anio=2011(1)2020{

use "$o2/Harvard/dataverse_files/country_partner_hsproduct4digit_year_`anio'.dta", clear

keep location_id product_id year export_value

merge m:1 location_id using "$o2/country_list"
keep if _merge == 3
drop _merge

merge m:1 product_id using "$o2/product_list"
keep if _merge == 3
drop _merge

preserve

*1. Subir matrices a Mata

/* Matriz de exportaciones pais-producto */ 
collapse (sum) export_value, by(product_id location_id)


rename export_value Xcp
fillin location_id product_id
replace Xcp = 0 if Xcp == .
drop _fillin

tostring product_id, replace
reshape wide Xcp, i(location_id) j(product_id) string

order location_id Xcp6* Xcp7* Xcp8* Xcp9* Xcp1* /* ordenar las variables (cod producto) de menor a mayor */

*mkmat Xcp*, matrix(Xcp)
*mata: Xcp = st_matrix("Xcp")
mata:  Xcp = st_data(., "Xcp*")

/* Vector de exportaciones por pais */

*reshape long Xcp, i(location_id) j(product_id)
restore, preserve

collapse (sum) export_value, by(location_id)
rename export_value EcXcp	

mkmat location_id, matrix(location_id)
mkmat EcXcp, matrix(EcXcp)
mata: EcXcp = st_matrix("EcXcp")

/* Vector de exportaciones por producto */
restore, preserve

collapse (sum) export_value, by(product_id)
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

*2. Cálculo de la matriz Mcp

mata{

Mcp = J(rows(Xcp),cols(Xcp),.)

for (i=1;i<=rows(Xcp);i++){
for (j=1;j<=cols(Xcp);j++){

Mcp[i,j] = (Xcp[i,j]/EcXcp[i,.])/(EpXcp[j,.]/EcpXcp)

if (Mcp[i,j] >= 1) Mcp[i,j] = 1
if (Mcp[i,j] < 1) Mcp[i,j] = 0

}
}

*3. Generación del ECI

kc0 = rowsum(Mcp) /* Diversidad */
kp0 = colsum(Mcp) /* Ubicuidad */

D = diag(kc0)
U = diag(kp0)

S = Mcp*pinv(U)*Mcp'
Mcc = pinv(D)*S

eigensystem(Mcc,Vc=.,lc=.)
kc=Re(Vc[.,2]) 

checksign = 2*((kc[41,.]) > 0 ) - 1

kc=kc :* checksign

st_matrix("kc", kc)
}

/* trasladar el ECI y los product_id a variables en Stata*/
drop *
svmat kc, names(col)
svmat location_id, names(col)
rename c1 eci

merge 1:1 location_id using "$o2/country_list", keepusing(location_code)
keep if _merge == 3
drop _merge

tempvar aux1 aux2
egen `aux1' = sd(eci)
egen `aux2' = mean(eci)
replace eci = (eci-`aux2')/`aux1'
drop `aux1' `aux2'

order location_id location_code eci

save "$o3/ICE_`anio'", replace

*4. Generación del PCI
mata{

Mpp = pinv(U)*Mcp'*pinv(D)*Mcp

eigensystem(Mpp,Vp=.,lp=.)
kp=Re(Vp[.,2]) 

/* falta realizar un checksign para kp */
checksign = 2*((kp[752,.]) > 0 ) - 1

kp=kp :* checksign

st_matrix("kp", kp)
}

/* trasladar el PCI y los product_id a variables en Stata*/
drop *
svmat kp, names(col)
rename c1 pci
*svmat product_id, names(col)
getmata product_id


merge 1:1 product_id using "$o2/product_list", keepusing(hs_product_code)
keep if _merge == 3
drop _merge

tempvar aux1 aux2
egen `aux1' = sd(pci)
egen `aux2' = mean(pci)
replace pci = (pci-`aux2')/`aux1'
drop `aux1' `aux2'

order product_id hs_product_code pci

save "$o3/PCI_`anio'", replace
}

******
* 5. Juntar ECI y PCI en formato panel
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

*1. PCI

/* colocar año a cada data set */
forv anio=1995(1)2020{
	
	use "$o3/PCI_`anio'", clear
	gen year = `anio'
	order year
	
	save "$o3/PCI_`anio'", replace
} 

/* append data set */

use "$o3/PCI_1995", clear

forv anio=1996(1)2020{
	
	append using "$o3/PCI_`anio'"
	
} 

save "$o3/PCI_1995-2020", replace 