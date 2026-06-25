export type Reward = {
	key: string,
	subKey: string,
	amount: number,
}

export type CodeCondition = {
	groupId: number?,
	minAccountAgeDays: number?,
	expiresAt: number?,
}

export type CodeEntry = {
	enabled: boolean,
	rewards: { Reward },
	maxRedemptions: number?,
	condition: CodeCondition?,
}

local CodesConfig: { [string]: CodeEntry } = {
	RELEASE = {
		enabled = true,
		rewards = {
			{ key = "currency", subKey = "coins", amount = 2500 },
		},
	},

	WELCOME = {
		enabled = true,
		rewards = {
			{ key = "currency", subKey = "coins", amount = 1000 },
		},
	},

	LIMITED100 = {
		enabled = true,
		maxRedemptions = 100,
		rewards = {
			{ key = "currency", subKey = "coins", amount = 5000 },
		},
	},

	GROUPONLY = {
		enabled = true,
		condition = {
			groupId = 0,
			minAccountAgeDays = 3,
		},
		rewards = {
			{ key = "currency", subKey = "coins", amount = 1500 },
		},
	},
}

return CodesConfig