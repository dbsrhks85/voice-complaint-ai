import asyncio
from database import init_supabase, get_supabase

async def check_data():
    await init_supabase()
    supabase = get_supabase()
    result = await supabase.table("complaints").select("id, attachment_urls, users(nickname)").limit(5).execute()
    for r in result.data:
        print(f"ID: {r['id']}, Attachments: {r['attachment_urls']}, Nickname: {r.get('users', {}).get('nickname')}")

if __name__ == "__main__":
    asyncio.run(check_data())
