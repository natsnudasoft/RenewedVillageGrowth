require("version.nut");
require("cargo.nut");
require("industry.nut");
require("town.nut");
require("company.nut");
require("subsidies.nut")
require("story.nut");
require("strings.nut");

// Import SuperLib for GameScript
import("util.superlib", "SuperLib", 40);
Log <- SuperLib.Log;
Helper <- SuperLib.Helper;

// Import ToyLib
import("Library.GSToyLib", "GSToyLib", 2);
import("Library.SCPLib", "SCPLib", 45);

enum Randomization {
    NONE = 1,
    INDUSTRY_DESC = 2,
    INDUSTRY_ASC = 3,
    FIXED_1 = 4,
    FIXED_2 = 5,
    FIXED_3 = 6,
    FIXED_5 = 7,
    FIXED_7 = 8,
    RANGE_1_2 = 9,
    RANGE_1_3 = 10,
    RANGE_2_3 = 11,
    RANGE_3_5 = 12,
    RANGE_3_7 = 13,
    DESCENDING = 14,
    ASCENDING = 15,
};

enum InitError {
    NONE,
    CARGO_LIST,
    INDUSTRY_LIST,
    TOWN_NUMBER,
    TOWN_GROWTH_RATE,
}

class MainClass extends GSController
{
    companies = null;
    towns = null;
    current_date = null;
    current_week = null;
    current_month = null;
    current_year = null;
    gs_init_done = null;
    load_saved_data = null;
    current_save_version = null;
    actual_town_info_mode = null;
    toy_lib = null;
    story_editor = null;

    constructor() {
        this.companies = [];
        this.towns = [];
        this.current_date = 0;
        this.current_week = 0;
        this.current_month = 0;
        this.current_year = 0;
        this.gs_init_done = false;
        this.current_save_version = SELF_MAJORVERSION;    // Ensures compatibility between revisions
        this.load_saved_data = false;
        this.actual_town_info_mode = 0;
        this.toy_lib = null;
        this.story_editor = null;
        ::TownDataTable <- {};
        ::CompanyDataTable <- {};
        ::SettingsTable <- {};
    }
}

function MainClass::Start()
{
    // Wait random number of ticks (less than one day) based on system time to ensure random number seed
    local sysdate = GSDate.GetSystemTime() % 70 + 1;
    this.Sleep(sysdate);

    // Initializing the script
    local start_tick = GSController.GetTick();

    // Read the openttd.cfg Town Growth Rate setting first.
    // If the map is set to disallow town growth at all, this script
    // won't do anything further.
    if (GSGameSettings.IsValid("town_growth_rate")) {
        if (! GSGameSettings.GetValue("town_growth_rate") ) {
            GSLog.Error("You must set town growth in advanced setting to something other than None. This script is now exiting!");
            this.story_editor = StoryEditor();
            this.story_editor.CreateStoryBook([], 0, InitError.TOWN_GROWTH_RATE);
            return;
        }
    }

    GSLog.Info("GameScript Peaks and Troughs loaded");
    
    local preset_setting = MainClass.GetSetting("pt_preset");
    local time_rates = [];
    switch(preset_setting)
    {
        case 1:
            GSLog.Info("Preset: Hyper peak");
            time_rates = [0.33, 0.19, 0.06, 0.06, 0.06, 0.23, 0.47, 0.76, 1.73, 1.03, 0.81, 0.76, 0.76, 0.76, 0.76, 0.83, 1.05, 1.32, 1.44, 1.32, 0.91, 0.76, 0.47, 0.4];
            break;
        case 2:
            GSLog.Info("Preset: Equal peaks");
            time_rates = [0.38, 0.22, 0.06, 0.06, 0.06, 0.22, 0.43, 1.11, 1.58, 0.98, 0.78, 0.73, 0.73, 0.73, 0.73, 0.82, 0.91, 1.21, 1.49, 1.36, 0.96, 0.81, 0.53, 0.46];
            break;
        case 3:
            GSLog.Info("Preset: Japan");
            time_rates = [0.51, 0.28, 0.05, 0.05, 0.05, 0.25, 0.61, 1.31, 1.87, 0.88, 0.65, 0.65, 0.65, 0.65, 0.65, 0.65, 0.78, 1.02, 1.24, 1.16, 1.03, 0.93, 0.81, 0.7];
            break;
        case 4:
            GSLog.Info("Preset: UK");
            time_rates = [0.08, 0.05, 0.05, 0.05, 0.06, 0.16, 0.38, 0.86, 1.75, 1.16, 1.03, 1.03, 1.03, 0.99, 1.0, 1.66, 1.18, 1.1, 0.99, 0.74, 0.52, 0.38, 0.31, 0.25];
            break;
        case 5:
            GSLog.Info("Preset: No peaks");
            time_rates = [0.06, 0.06, 0.06, 0.06, 0.06, 0.06, 0.06, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 1.07, 0.06, 0.06];
            break;
        default:
            GSLog.Error("Failed to recognise preset");
    }
    local base_production = MainClass.GetSetting("pt_base_prod");
    GSLog.Info("Base Production: "+base_production);

    local base_rates = MainClass.GetSetting("pt_base");
    GSLog.Info("Offset: "+base_rates);
    
    local logs = MainClass.GetSetting("pt_log_level");

    GSGame.Pause();
    Log.Info("Script initialisation...", Log.LVL_INFO);
    local init_error = this.Init();
    GSGame.Unpause();

    local setup_duration = GSController.GetTick() - start_tick;
    Log.Info("Game setup done.", Log.LVL_INFO);
    Log.Info("Setup took " + setup_duration + " ticks.", Log.LVL_DEBUG);
    Log.Info("Happy playing !", Log.LVL_INFO);

    // Wait for the game to start
    GSController.Sleep(1);

    // Create and fill StoryBook. This can't be done before OTTD is ready.
    this.story_editor = StoryEditor();
    this.story_editor.CreateStoryBook(this.companies, this.towns.len(), init_error);

    if (!this.gs_init_done) {
        GSLog.Error("Game initialisation failed. This script is now exiting!");
        return;
    }
    
    if("GetHour" in GSDate) {
        // Main loop
        GSLog.Info("Correct version of JGR loaded");
        local past_system_time = GSDate.GetSystemTime();
        local previous_time = -1;
        
        while (true) {
            local loop_start_tick = GSController.GetTick();
            
            //get time
            local tick_scale = GSDate.GetCurrentScaledDateTicks();
            local current_time = GSDate.GetHour(tick_scale);
            if (previous_time != current_time) {
                //failsafe
                if(current_time >= 24) {
                    if (logs != 1) {
                        GSLog.Warning("GetHour returned "+current_time);	
                        GSLog.Info("Hours set to 0");
                    }
                    
                    current_time = 0;
                }
                
                previous_time = current_time;
                
                local base_modifier = 1.0 + (base_rates * 0.1);
                local prod_rate = base_production * time_rates[current_time] * base_modifier;
                prod_rate = floor(prod_rate + 0.5).tointeger();
                
                if (logs == 3) {
                    GSLog.Info("Time: " + current_time + ", Production: " + base_production + "*" + time_rates[current_time] + "*" + base_modifier + "=" + prod_rate);
                }
                
                GSGameSettings.SetValue("economy.town_cargo_scale", prod_rate);
                GSGameSettings.SetValue("economy.town_cargo_scale_mode", 1);
            }


            local town_info_mode = GSController.GetSetting("town_info_mode");
            if (this.actual_town_info_mode != town_info_mode) {
                this.actual_town_info_mode = town_info_mode;
                foreach (town in this.towns) {
                    town.UpdateTownText(this.actual_town_info_mode);
                }
                continue;
            }

            local system_time = GSDate.GetSystemTime();
            if (1 == this.actual_town_info_mode && system_time - past_system_time > 3) {
                past_system_time = system_time;

                foreach (town in this.towns) {
                    town.UpdateTownText(this.actual_town_info_mode);
                }
            }

            this.HandleEvents();
            this.ManageTowns();
        }
    } else {
        GSLog.Error("Please update to a newer version of JGR patch pack");
    }
}

function MainClass::Init()
{
    this.toy_lib = GSToyLib(null); // Init ToyLib;

    // Check game settings
    GSGameSettings.SetValue("economy.town_growth_rate", 2);
    GSGameSettings.SetValue("economy.fund_buildings", 0);
    ::SettingsTable.wallclock_timekeeping <- GSGameSettings.GetValue("economy.timekeeping_units");

    if (!this.load_saved_data) { // Disallow changing these in a running game
        ::SettingsTable.use_town_sign <- GSController.GetSetting("use_town_sign");
        ::SettingsTable.randomization <- GSController.GetSetting("cargo_randomization");
        ::SettingsTable.display_cargo <- GSController.GetSetting("display_cargo");
        ::SettingsTable.cargo_6_category <- GSController.GetSetting("cargo_6_category");
        ::SettingsTable.category_min_pop <- [GSController.GetSetting("category_1_min_pop"),
                                             GSController.GetSetting("category_2_min_pop"),
                                             GSController.GetSetting("category_3_min_pop"),
                                             GSController.GetSetting("category_4_min_pop"),
                                             GSController.GetSetting("category_5_min_pop"),
                                             GSController.GetSetting("category_6_min_pop")];
        ::SettingsTable.initial_subsidies_created <- false;
    }

    // Set current date
    this.current_date = this.current_week = GSDate.GetCurrentDate();
    this.current_month = GSDate.GetMonth(this.current_date);
    this.current_year = GSDate.GetYear(this.current_date);

    if (::SettingsTable.randomization == Randomization.INDUSTRY_DESC
     || ::SettingsTable.randomization == Randomization.INDUSTRY_ASC) {
        if (!InitIndustryLists())
            return InitError.INDUSTRY_LIST;
    }
    else {
        // Initialize cargo lists and variables
        if (!InitCargoLists())
            return InitError.CARGO_LIST;
    }

    /* Check whether saved data are in the current save
     * format.
     */
    if (!this.load_saved_data) {
        Helper.ClearAllSigns();
    }

    // Create company list
    Log.Info("Creating company list ...", Log.LVL_INFO);
    this.companies = this.CreateCompanyList();

    // Create the towns list
    Log.Info("Creating town list ... (can take a while on large maps)", Log.LVL_INFO);
    this.towns = this.CreateTownList();
    if (this.towns.len() > SELF_MAX_TOWNS)
        return InitError.TOWN_NUMBER;
    Log.Info("Setup " + this.towns.len() + " towns", Log.LVL_INFO);

    // Run industry stabilizer
    Log.Info("Prospecting raw industries ... (can take a while on large maps)", Log.LVL_INFO);
    ProspectRawIndustry();

    // Ending initialization
    this.gs_init_done = true;

    return InitError.NONE;
}

function MainClass::HandleEvents()
{
    while (GSEventController.IsEventWaiting()) {
        local event = GSEventController.GetNextEvent();

        if (event == null)
            return;

        switch (event.GetEventType()) {
        // On town founding, add a new GoalTown instance
        case GSEvent.ET_TOWN_FOUNDED:
            event = GSEventTownFounded.Convert(event);
            local town_id = event.GetTownID();
            if (GSTown.IsValidTown(town_id)) this.UpdateTownList(town_id);
            break;

        case GSEvent.ET_COMPANY_NEW:
        case GSEvent.ET_COMPANY_BANKRUPT:
        case GSEvent.ET_COMPANY_MERGER:
            Log.Info("A company was created/bankrupt/merged => update company list", Log.LVL_INFO);
            this.UpdateCompanyList();
            break;

        default: break;
        }
    }
}

function MainClass::Save()
{
    Log.Info("Saving data...", Log.LVL_INFO);
    local save_table = {};

    /* If the script isn't yet initialized, we can't retrieve data
     * from GoalTown instances. Thus, simply use the original
     * loaded table. Otherwise we build the table with town data.
     */
    save_table.company_data_table <- {};
    save_table.town_data_table <- {};
    if (!this.gs_init_done) {
        save_table.town_data_table <- ::TownDataTable;
    } else {
        // Save permanent settings (allows changing them in scenario editor)
        save_table.use_town_sign <- ::SettingsTable.use_town_sign;
        save_table.randomization <- ::SettingsTable.randomization;
        save_table.display_cargo <- ::SettingsTable.display_cargo;
        save_table.cargo_6_category <- ::SettingsTable.cargo_6_category;
        save_table.category_min_pop <- ::SettingsTable.category_min_pop;
        save_table.initial_subsidies_created <- ::SettingsTable.initial_subsidies_created;

        foreach (company in this.companies)
        {
            save_table.company_data_table[company.id] <- company.SavingCompanyData();
        }

        local start_opcodes = GSController.GetOpsTillSuspend();
        foreach (i, town in this.towns)
        {
            save_table.town_data_table[town.id] <- town.SavingTownData();
        }
        Log.Info("Opcodes per saved town = " + ((start_opcodes - GSController.GetOpsTillSuspend()) / this.towns.len()), Log.LVL_DEBUG);
        // Also store a savegame version flag
        save_table.save_version <- this.current_save_version;
    }

    return save_table;
}

function MainClass::Load(version, saved_data)
{
    Log.Info("Loading data...", Log.LVL_INFO);
    // Loading town data. Only load data if the savegame version matches.
    if ((saved_data.rawin("save_version") && saved_data.save_version == this.current_save_version)) {
        this.load_saved_data = true;
        ::SettingsTable.use_town_sign <- saved_data.use_town_sign;
        ::SettingsTable.randomization <- saved_data.randomization;
        ::SettingsTable.display_cargo <- saved_data.display_cargo;
        ::SettingsTable.cargo_6_category <- saved_data.cargo_6_category;
        ::SettingsTable.category_min_pop <- saved_data.category_min_pop;
        if ("initial_subsidies_created" in saved_data) {
            ::SettingsTable.initial_subsidies_created <- saved_data.initial_subsidies_created;
        } else {
            ::SettingsTable.initial_subsidies_created <- false;
        }

        foreach (companyid, company_data in saved_data.company_data_table) {
            ::CompanyDataTable[companyid] <- company_data;
        }

        foreach (townid, town_data in saved_data.town_data_table) {
            ::TownDataTable[townid] <- town_data;
        }
    }
    else {
        Log.Info("Save data format doesn't match with current version (saved " + saved_data.save_version + " vs current " + this.current_save_version + "). Resetting.", Log.LVL_INFO);
    }
}

function MainClass::UpdateCompanyList()
{
    for(local c = GSCompany.COMPANY_FIRST; c <= GSCompany.COMPANY_LAST; c++)
    {
        local existing = null;
        local existing_idx = 0;
        foreach(index, company in this.companies)
        {
            if(company.id == c)
            {
                existing = company;
                existing_idx = index;
                break;
            }
        }

        if(GSCompany.ResolveCompanyID(c) == GSCompany.COMPANY_INVALID)
        {
            if(existing != null) {
                existing.RemoveGUIGoals();
                this.companies.remove(existing_idx);
            }

            continue;
        }

        // If the company can be resolved and exists => do anything
        if(existing != null) continue;

        // Initialize new company
        local company = Company(c, false);
        this.companies.append(company);

        if (this.story_editor != null)
            this.story_editor.CreateNewCompanyStoryBook(company);
    }
}

function MainClass::CreateCompanyList()
{
    this.companies = [];

    // Create company list from saved data
    if (this.load_saved_data && ::CompanyDataTable != null) {
        foreach (company_id, company_data in ::CompanyDataTable)
        {
            this.companies.append(Company(company_id, true));
        }
    }

    // Now we can free ::CompanyDataTable
    ::CompanyDataTable = null;

    // Update company list for created/bankrupted/merged
    this.UpdateCompanyList();

    return companies;
}

/* Make a squirrel array of GoalTown instances (towns_array). For each
 * town, an instance of GoalTown is created to store the data related
 * to that town.
 */
function MainClass::CreateTownList()
{
    // In multiplayer, pause level cannot be changed, so monthly update is forced at start to finish initialization
    // In single player, if it is not set, temporarily allow all non-construction actions during pause
    local pause_level = GSGameSettings.GetValue("construction.command_pause_level");
    if (GSGame.IsMultiplayer() && pause_level < 1)
        this.current_month -= 1;
    else if (pause_level < 1)
        GSGameSettings.SetValue("construction.command_pause_level", 1);

    // Create list of cargos/industries near each town
    local near_town;
    if (::SettingsTable.randomization == Randomization.INDUSTRY_DESC ||
        ::SettingsTable.randomization == Randomization.INDUSTRY_ASC)
        near_town = GetTownsNearbyIndustryPerCategory();
    else
        near_town = GetTownsNearbyCargoPerCategory();

    local towns_list = GSTownList();
    local towns_array = [];

    local min_transport = GSController.GetSetting("limit_min_transport");
    local near_cargo_probability = GSController.GetSetting("near_cargo_probability");
    foreach (t, _ in towns_list) {
        towns_array.append(GoalTown(t, this.load_saved_data, min_transport, near_town[t], near_cargo_probability));
    }

    // Reset to previous settings
    GSGameSettings.SetValue("construction.command_pause_level", pause_level);

    // Now we can free ::TownDataTable
    ::TownDataTable = null;

    return towns_array;
}

/* Function called on town creation. We need to add a now GoalTown
 * instance to the this.towns array. The array order doesn't matter,
 * since we never use the array index, only its values.
 */
function MainClass::UpdateTownList(town_id)
{
    // Create list of cargos/industries near each town
    local near_town;
    if (::SettingsTable.randomization == Randomization.INDUSTRY_DESC ||
        ::SettingsTable.randomization == Randomization.INDUSTRY_ASC)
        near_town = GetTownsNearbyIndustryPerCategory();
    else
        near_town = GetTownsNearbyCargoPerCategory();

    local min_transport = GSController.GetSetting("limit_min_transport");
    local near_cargo_probability = GSController.GetSetting("near_cargo_probability");
    this.towns.append(GoalTown(town_id, false, min_transport, near_town[town_id], near_cargo_probability));
    Log.Info("New town founded: "+GSTown.GetName(town_id)+" (id: "+town_id+")", Log.LVL_DEBUG);
}

function MainClass::DailyManageTownPopulation()
{
    foreach (town in this.towns) {
        local new_population = GSTown.GetPopulation(town.id);
        if (new_population > town.max_population) {
            foreach (company in companies) {
                if (company.id == town.contributor) {
                    company.AddPoints(new_population - town.max_population);
                    Log.Info(GSTown.GetName(town.id)
                             + " increased population by " + (new_population - town.max_population)
                             + " which was added to " + GSCompany.GetName(company.id), Log.LVL_DEBUG);
                }
            }

            town.max_population = new_population;
        }
    }
}

/* Function called periodically (each 74 ticks) to manage
 * towns and other stuff.
 */
function MainClass::ManageTowns()
{
    // Run the daily functions
    local date = GSDate.GetCurrentDate();
    local diff_date = date - this.current_date;
    if (diff_date == 0) {
        return;
    } else {
        GSToyLib.Check();
        this.story_editor.CheckParameters(this.companies);
        DailyManageTownPopulation();

        this.current_date = date;
    }

    // Run the monthly functions
    local month = GSDate.GetMonth(date);
    local diff_month = month - this.current_month;
    if (diff_month == 0) {
        return;
    } else {
        local month_tick = GSController.GetTick();
        Log.Info("Starting Monthly Updates...", Log.LVL_INFO);

        local eternal_love = GSController.GetSetting("eternal_love");
        local eternal_love_rating = 0;
        switch (eternal_love) {
            case(1): // Outstanding
                eternal_love_rating = 1000;
                break;
            case(2): // Good
                eternal_love_rating = 400;
                break;
            case(3): // Poor
                eternal_love_rating = 0;
                break;
        }

        local threshold_setting = GSController.GetSetting("town_size_threshold");
        local min_transport = GSController.GetSetting("limit_min_transport");
        foreach (town in this.towns) {
            town.ManageTownLimiting(threshold_setting, min_transport);
            town.MonthlyManageTown();
            if (this.actual_town_info_mode > 1) {
                town.UpdateTownText(this.actual_town_info_mode);
            }

            if (eternal_love > 0) {
                town.EternalLove(eternal_love_rating);
            }
        }

        foreach (company in this.companies) {
            company.MonthlyUpdateGUIGoals(this.towns);
        }

        this.current_month = month;
        local month_tick_duration = GSController.GetTick() - month_tick;
        Log.Info("Monthly Update took "+month_tick_duration+" ticks.", Log.LVL_DEBUG);
    }

    // Run the yearly functions - Nothing to do for now, so we leave it out
    local year = GSDate.GetYear(date);
    local diff_year = year - this.current_year;
    if ( diff_year == 0 && ::SettingsTable.initial_subsidies_created )
        return;
    else
    {
        if (diff_year != 0) {
            Log.Info("Starting Yearly Updates...", Log.LVL_INFO);

            ProspectRawIndustry();
        }
        
        local success = CreateSubsidies(towns, companies);
        ::SettingsTable.initial_subsidies_created = ::SettingsTable.initial_subsidies_created || success;

        this.current_year = year;
    }
}

function Modulo(num, divisor) {
    return (num - divisor * (num / divisor));
}