local STORE_VERSION = "1"

local DataTemplate = {
	currency = {
		coins = 0,
	},

	meta = {
		redeemedCodes = {} :: { [string]: number },
	},
}

DataTemplate._STORE_VERSION = STORE_VERSION
DataTemplate._STORE_NAME    = "PlayerData_" .. STORE_VERSION

return DataTemplate	