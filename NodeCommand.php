<?php

namespace Pterodactyl\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Ramsey\Uuid\Uuid;
use Illuminate\Support\Str;
use Pterodactyl\Models\Node;
use Illuminate\Contracts\Encryption\Encrypter;

class NodeCommand extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'command:node';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Command description';

    /**
     * @var \Illuminate\Contracts\Encryption\Encrypter
     */
    private $encrypter;

    /**
     * Create a new command instance.
     *
     * @return void
     */
    public function __construct(Encrypter $encrypter)
    {
        parent::__construct();
        $this->encrypter = $encrypter;
    }

    /**
     * Execute the console command.
     *
     * @return int
     */
    public function handle()
    {
        $uuid = Uuid::uuid4()->toString();
        $daemon_token = $this->encrypter->encrypt(Str::random(Node::DAEMON_TOKEN_LENGTH));
        $daemon_token_id = Str::random(Node::DAEMON_TOKEN_ID_LENGTH);

        DB::table('nodes')->insert(['uuid' => $uuid, 'name' => 'Node 01', 'description' => 'Script gemaakt door Maikel', 'location_id' => '1', 'fqdn' => '45.13.59.15', 'scheme' => 'http', 'behind_proxy' => '0', 'maintenance_mode' => '0', 'memory' => '8000', 'memory_overallocate' => '-1', 'disk' => '80000', 'disk_overallocate' => '-1', 'upload_size' => '100', 'daemon_token_id' => $daemon_token_id, 'daemon_token' => $daemon_token, 'daemonListen' => '8080', 'daemonSFTP' => '2022', 'daemonBase' => '/var/lib/pterodactyl/volumes']);
    }
}
